# Knowledge Base Library Layout

## Status

Component plan and implementation-status document for the Lean library layout of the knowledge base.
This document refines the overall knowledge base plan in `plans/knowledgebase.md` and complements the storage, node, metadata, serialization, CLI, validation, search, repair, and indexing component plans.

## Component implementation status

- Overall status: Implemented in initial usable form
- Implemented in code: Yes
- Last updated basis: current `AFTK/KnowledgeBase/*` module tree plus `AFTK/KnowledgeBase/Cli/*`, with project-wide tests living separately under `AFTKTest/KnowledgeBase/*`

## Purpose

This document describes how the knowledge base should be laid out in the Lean source tree.
It is about **library/module structure**, not the filesystem layout of canonical knowledge-base content.
That separate on-disk storage design is defined in `plans/knowledgebase/storage.md`.

The goal is to make implementation start from a clear module structure rather than accumulating logic ad hoc in `Main.lean` or in one oversized file.

Code has now been added.
This file remains the design reference and status tracker for the implemented library layout.

## Design goals

The knowledge-base library layout should:

- present a clear, stable import surface for the rest of the system
- separate reusable library logic from CLI-only concerns
- keep dependency direction simple and acyclic
- align code boundaries with the existing design documents where practical
- avoid premature over-fragmentation into too many tiny modules
- make it easy to grow from a minimal first implementation into richer validation, search, repair, and indexing support
- isolate optional bundled-Lake dependencies so they do not leak through the whole library unnecessarily

Lean module and namespace naming for this layer should use `KnowledgeBase` rather than the abbreviation `KB`.

## Scope and non-scope

### In scope

- Lean module and file layout under `AFTK/KnowledgeBase/`
- the boundary between reusable knowledge-base library code and executable/CLI code
- recommended dependency direction between module groups
- the initial public import surface for the knowledge-base layer

### Out of scope

- the on-disk canonical storage layout for node files
- the detailed metadata schema itself
- the exact command-line surface
- the exact internal format of derived indexes

Those are covered respectively by:

- `plans/knowledgebase/storage.md`
- `plans/knowledgebase/metadata.md`
- `plans/knowledgebase/cli.md`
- `plans/knowledgebase/indexing.md`

## Naming conventions

The intended Lean naming conventions for this layer are:

- namespace root: `AFTK.KnowledgeBase`
- library modules: `AFTK/KnowledgeBase/...`
- CLI-specific modules: `AFTK/KnowledgeBase/Cli/...`
- public library root module: `AFTK/KnowledgeBase.lean`

The public executable should still be invoked through:

```text
lake exe aftk knowledgebase ...
```

That is a CLI naming decision.
The library layout should support it, but should not collapse all knowledge-base logic into the executable entrypoint.

## Layout principles

### 1. Keep the reusable library separate from the executable

The knowledge-base layer should be usable from:

- the `aftk` executable
- later Lean code in the informal layer
- tests
- small internal integration utilities

Accordingly, the main knowledge-base logic should live in ordinary library modules under `AFTK/KnowledgeBase/`.
`Main.lean` should only be a thin executable entrypoint and command dispatcher.

### 2. Keep low-level domain types near the bottom of the dependency graph

Core types such as `NodeId`, `Timestamp`, `Relationship`, `NodeMetadata`, and `StorageManifest` should live in low-level modules that do not depend on CLI parsing, search, validation, or repair code.

This keeps the foundational concepts reusable and reduces the risk of circular imports.

### 3. Separate path/layout logic from storage operations

Mapping a `NodeId` to canonical paths is a different concern from reading, writing, scanning, validating, or searching the knowledge base.

A small path/layout module should therefore hold things like:

- `NodeId` to relative path-stem conversion
- canonical `.md` / `.json` sibling path computation
- storage-root path records
- manifest/path helper functions

Higher-level modules can then build on those helpers without duplicating path logic.

### 4. Keep canonical serialization logic distinct from CLI rendering

The knowledge base has two different JSON surfaces:

- canonical on-disk JSON for manifests and metadata
- CLI JSON output for automation

Those should not be conflated in the source layout.
Canonical JSON parsing/writing belongs with storage and serialization modules.
CLI output rendering belongs under CLI modules.

### 5. Validation, search, repair, and indexing should sit above storage

These are higher-level services.
They should consume the core storage and serialization layers rather than becoming places where canonical file manipulation logic is reimplemented.

### 6. Start coarse-grained, then split only when code size justifies it

The first implementation should not create a separate Lean file for every tiny type.
A modest number of well-chosen modules is better than an explosion of files before any code exists.

If a coarse module becomes too large later, it can be split along the same boundaries already described in the design docs.

## Recommended initial module layout

The first implementation should likely start with a layout close to this:

```text
AFTK.lean
AFTK/KnowledgeBase.lean
AFTK/KnowledgeBase/Types.lean
AFTK/KnowledgeBase/PathLayout.lean
AFTK/KnowledgeBase/Serialization.lean
AFTK/KnowledgeBase/Storage.lean
AFTK/KnowledgeBase/Validation.lean
AFTK/KnowledgeBase/Search.lean
AFTK/KnowledgeBase/Repair.lean
AFTK/KnowledgeBase/Indexing.lean
AFTK/KnowledgeBase/Cli/Types.lean
AFTK/KnowledgeBase/Cli/Parse.lean
AFTK/KnowledgeBase/Cli/Render.lean
AFTK/KnowledgeBase/Cli/Main.lean
Main.lean
```

This is intentionally pragmatic rather than maximally granular.
It is enough structure to keep responsibilities clear without forcing the first implementation into unnecessary fragmentation.

## Module responsibilities

### `AFTK.lean`

This is the root of the `AFTK` library.
As the project grows, it should import stable library entrypoints such as `AFTK.KnowledgeBase`.
It should not import executable-only modules.

### `AFTK/KnowledgeBase.lean`

This should be the curated public root for the knowledge-base library.
It should re-export the reusable knowledge-base modules that other Lean code may reasonably import.

It should typically import modules such as:

- `AFTK.KnowledgeBase.Types`
- `AFTK.KnowledgeBase.PathLayout`
- `AFTK.KnowledgeBase.Serialization`
- `AFTK.KnowledgeBase.Storage`
- `AFTK.KnowledgeBase.Validation`
- `AFTK.KnowledgeBase.Search`
- `AFTK.KnowledgeBase.Repair`
- `AFTK.KnowledgeBase.Indexing`

It should not import `AFTK.KnowledgeBase.Cli.*`.
The CLI is a consumer of the library, not part of the reusable library surface.

### `AFTK/KnowledgeBase/Types.lean`

This should hold the core domain types shared across the layer, such as:

- `NodeId`
- `Timestamp`
- `NodeKind`
- `NodeStatus`
- `RelationshipKind`
- `Relationship`
- `LeanDeclRef`
- `NodeMetadata`
- `StorageManifest`
- small shared record types used across storage, validation, and search

This module is a good place for:

- simple invariants
- lightweight helper functions
- straightforward `deriving` clauses
- basic JSON instance declarations for leaf types where appropriate

It should stay free of CLI parsing and command-dispatch logic.

### `AFTK/KnowledgeBase/PathLayout.lean`

This should define the code-level layout rules that connect library types to storage paths, including:

- `NodeId` to relative path-stem conversion
- path-stem to `.md` / `.json` sibling path derivation
- root path bundles such as `KnowledgeBaseStoragePaths`
- helper functions for `manifest.json`, `nodes/`, and `.aftk/` paths
- canonical root/path normalization helpers

This module should not read or write files itself except perhaps through tiny helper wrappers if that turns out to be unavoidable.
Its main role is deterministic path computation.

### `AFTK/KnowledgeBase/Serialization.lean`

This should centralize canonical serialization logic for the knowledge-base layer, including:

- strict parsing of `StorageManifest`
- strict parsing of `NodeMetadata`
- deterministic writing of canonical JSON
- Markdown body read/write normalization helpers
- wrapper parsing/formatting for `NodeId` and `Timestamp`

This module should be where the project-local strictness policy lives, especially:

- unknown-field rejection for canonical JSON
- canonical omission/default rules
- canonical field ordering or sorted-key policy
- newline handling for emitted files

CLI JSON rendering should not live here.

### `AFTK/KnowledgeBase/Storage.lean`

This should implement direct storage operations over the canonical knowledge-base tree, such as:

- root initialization
- root resolution/path construction
- reading a node body
- reading metadata
- writing body/metadata updates
- listing/scanning nodes
- rename/create/delete primitives if those are treated as direct storage operations

This module should use `PathLayout` and `Serialization` instead of duplicating their logic.

If later needed, this module can be split into things like `Root`, `NodeStore`, or `Mutation`, but the first implementation does not need that split.

### `AFTK/KnowledgeBase/Validation.lean`

This should define:

- validation issue types
- validation report/result types
- node/storage/relationship validation routines

It should depend on the storage and serialization layers for actual data access.
It should not become a second storage implementation.

### `AFTK/KnowledgeBase/Search.lean`

This should define:

- search query/result types
- direct-scan search routines over canonical storage
- later optional hooks into derived indexes

The first implementation can stay simple and storage-backed.
Index awareness can remain a later extension behind the same general search API.

### `AFTK/KnowledgeBase/Repair.lean`

This should define:

- repair-plan types
- dry-run/apply semantics
- normalization and cleanup routines that build on validation/storage

Repair is higher-level behavior and should therefore depend on storage/validation rather than embedding its own ad hoc parsing and traversal rules.

### `AFTK/KnowledgeBase/Indexing.lean`

This should define:

- derived index types and manifests
- full-rebuild logic
- helpers for optional search/relationship acceleration

Because indexes are rebuildable and noncanonical, this module should depend on the core storage/types modules rather than the reverse.

### `AFTK/KnowledgeBase/Cli/Types.lean`

This should hold CLI-only types such as:

- global options
- parsed command ASTs
- output-format selections
- small command-local option records

These are not canonical knowledge-base domain types.
They are part of the command-line interface layer and should stay separate from the reusable library core.

### `AFTK/KnowledgeBase/Cli/Parse.lean`

This should implement command-line parsing.
It is the natural place to use:

- `Lake.Util.Cli`
- command-family parsing helpers
- option processing and parse-time diagnostics

The parser should produce CLI AST values rather than directly performing storage operations.

### `AFTK/KnowledgeBase/Cli/Render.lean`

This should render command results for:

- human-readable text output
- stable CLI JSON output

This separation keeps the core library free of presentation-specific formatting logic.

### `AFTK/KnowledgeBase/Cli/Main.lean`

This should bridge the CLI parser and the reusable library.
Its responsibilities should include:

- command dispatch
- conversion of library errors into exit codes and user-facing diagnostics
- invoking text/JSON rendering
- coordination of global options such as `--root` and `--format`

It should remain fairly thin.
The real domain behavior should still live in the library modules above.

### `Main.lean`

This should be the executable entrypoint for the whole `aftk` program.
Initially it may just forward to the knowledge-base CLI.
Later, when additional layers gain CLIs, it can become a top-level dispatcher across subcommands such as:

- `knowledgebase`
- `informal`
- others added later

That top-level dispatch concern should stay here rather than leaking into the reusable knowledge-base library.

## Recommended dependency direction

The initial dependency shape should look roughly like this:

```text
Types
├── PathLayout
├── Serialization
└── Cli/Types

PathLayout + Serialization
└── Storage

Storage + Types
├── Validation
├── Search
└── Indexing

Storage + Validation
└── Repair

Cli/Types
└── Cli/Parse

Cli/Types + library result types
└── Cli/Render

Cli/Parse + Cli/Render + library modules
└── Cli/Main

Cli/Main
└── Main
```

The key rule is:

- CLI modules may depend on library modules
- higher-level service modules may depend on storage/serialization modules
- foundational modules should not depend upward on CLI/search/repair/indexing code

## Recommended first implementation order

A sensible implementation order for this layout would be:

1. `AFTK/KnowledgeBase/Types.lean`
2. `AFTK/KnowledgeBase/PathLayout.lean`
3. `AFTK/KnowledgeBase/Serialization.lean`
4. `AFTK/KnowledgeBase/Storage.lean`
5. `AFTK/KnowledgeBase/Cli/Types.lean`
6. `AFTK/KnowledgeBase/Cli/Parse.lean`
7. `AFTK/KnowledgeBase/Cli/Render.lean`
8. `AFTK/KnowledgeBase/Cli/Main.lean`
9. `Main.lean`
10. `Validation`, `Search`, `Repair`, and `Indexing` as the next wave

That order matches the broader plan's first implementation priorities and keeps the early code focused on the minimum viable library surface.

## Likely later refinement if the library grows

If the initial coarse modules become too large, the next split should follow the conceptual boundaries already defined by the other component plans.
For example, a later refinement might look like:

```text
AFTK/KnowledgeBase/
  NodeId.lean
  Timestamp.lean
  Metadata.lean
  Manifest.lean
  PathLayout.lean
  CanonicalJson.lean
  Markdown.lean
  Storage/
    Root.lean
    NodeStore.lean
    Mutation.lean
  Validation/
    Types.lean
    Run.lean
  Search/
    Types.lean
    Direct.lean
    IndexBacked.lean
  Cli/
    Types.lean
    Parse.lean
    Render.lean
    Main.lean
```

However, this finer split should be driven by code volume and implementation pressure, not by preemptive fragmentation before the first code exists.

## Lean 4 reuse findings for module boundaries

The earlier Lean/Lake source survey suggests the following layout choices.

- `System.FilePath`, `IO.FS`, `Lean.Data.Json`, and `Std.Time` can be used directly in the lower-level knowledge-base modules; no separate generic wrapper layer is needed in v1.
- If `Lake.Util.Cli`, `Lake.Util.MainM`, and `Lake.Util.Log` are used, they should be confined to `AFTK/KnowledgeBase/Cli/*` modules.
- If `Lake.Util.JsonObject` is used to simplify strict JSON decoding, it should stay inside `Serialization.lean` or a small serialization-focused helper module rather than becoming a ubiquitous dependency of all domain types.
- `Std.HashMap`, `Std.HashSet`, `Std.TreeMap`, and `Std.TreeSet` belong naturally in validation, search, and indexing modules rather than in the foundational path/layout layer.
- The public library root should export project domain concepts, not bundled Lake helper types directly.

## Open questions for later refinement

- Should broadly shared result/error types live in `Types.lean`, or should they get a separate `Error.lean` once implementation begins?
- Should create/read/update/delete functions live in `Storage.lean`, or should a separate higher-level service module be introduced once operations become richer?
- Should CLI JSON envelope/result types live under `Cli/Types.lean`, or should some of them be promoted into reusable library result modules for higher-layer integrations?
- Should `AFTK.lean` re-export `AFTK.KnowledgeBase` directly, or should the library root stay more selective as additional layers are added?

## Summary

The knowledge-base library should live under `AFTK/KnowledgeBase/` with a clear split between:

- foundational domain types
- path/layout helpers
- canonical serialization
- storage operations
- higher-level services such as validation, search, repair, and indexing
- CLI parsing/rendering/dispatch

The initial implementation should favor a small number of coarse but well-bounded modules.
That gives AFTK a practical starting structure while preserving a clean path to finer-grained modules later if the codebase grows.