# Knowledge Base Storage System

## Status

Design-only component plan for knowledge-base storage.
This document refines the overall knowledge base plan in `plans/knowledgebase.md` and works together with `plans/knowledgebase/node.md` and `plans/knowledgebase/metadata.md`.

## Component implementation status

- Overall status: Not implemented
- Implemented in code: No
- Last updated basis: design only

## Purpose

This document defines the filesystem-level storage system for the knowledge base.
It fixes the overall root-directory layout around the node design, distinguishes canonical data from derived state, and gives the storage model a concrete shape for later Lean implementation.

No code is being added yet.
This file is only a design target for later implementation.

## Design goals

The storage system should:

- keep the canonical knowledge base file-backed and human-inspectable
- make node lookup and traversal predictable
- clearly separate canonical data from generated or cached data
- be friendly to version control
- support future indexing and search without changing canonical storage
- align with the node and metadata designs already captured in the component plans

Lean module and namespace naming for this layer should use `KnowledgeBase` rather than the abbreviation `KB`.
The intended CLI command should likewise use `knowledgebase` rather than `kb`.

## Storage principles

### 1. Canonical data stays simple

The canonical knowledge base should be understandable from ordinary files alone.
The storage system should not require a database or opaque binary format in order to inspect or recover the knowledge base.

### 2. Canonical and derived data are different things

The storage design should clearly separate:

- **canonical data**: the real source of truth
- **derived data**: caches, indexes, temporary files, and other rebuildable artifacts

Only canonical data should be required to reconstruct the knowledge base.

### 3. The storage layout should be repository-local by default

The initial design should assume that the knowledge base lives inside the project repository, so that it is easy to review, diff, version, and move with the project.

## Proposed root layout

The initial canonical storage root should be:

```text
<repo-root>/knowledgebase/
```

Inside that root, the storage layout should be:

```text
knowledgebase/
  manifest.json
  nodes/
    topology/
      open_cover.md
      open_cover.json
    group/
      basic/
        definition.md
        definition.json
  .aftk/
    index/
    cache/
    tmp/
```

### Top-level meaning

- `knowledgebase/manifest.json` — root manifest describing the storage layout
- `knowledgebase/nodes/` — canonical node storage
- `knowledgebase/.aftk/` — derived/internal state, not canonical

This design gives the knowledge base a small, explicit root while reserving a place for noncanonical operational files.

## Why use `knowledgebase/` as the root

The initial design chooses `knowledgebase/` because it is:

- explicit and self-explanatory
- easy to recognize in the repository
- consistent with the CLI naming (`aftk knowledgebase ...`)
- consistent with the intended Lean naming (`AFTK.KnowledgeBase`)

This is only the initial design choice, but it is a good default unless later experience reveals a stronger need for a different name.

## Canonical storage

The canonical storage for the knowledge base consists of:

- `knowledgebase/manifest.json`
- all node `.md` and `.json` files under `knowledgebase/nodes/`

These are the files that should be treated as the source of truth.

### Canonical node paths

The node design defines a mapping from `NodeId` to a relative path stem such as:

- `topology.open_cover` -> `topology/open_cover`
- `group.basic.definition` -> `group/basic/definition`

The storage system fixes where that relative stem lives.
The full canonical paths become:

- `knowledgebase/nodes/<stem>.md`
- `knowledgebase/nodes/<stem>.json`

So, for example, the node `topology.open_cover` is stored canonically as:

- `knowledgebase/nodes/topology/open_cover.md`
- `knowledgebase/nodes/topology/open_cover.json`

## Root manifest

The storage root should contain a small manifest file:

```text
knowledgebase/manifest.json
```

The purpose of the manifest is to:

- make the knowledge-base root self-describing
- support future evolution of the storage layout
- make root discovery and validation more explicit
- avoid hard-coding too many assumptions without a versioned record

### Proposed manifest shape

```json
{
  "schemaVersion": 1,
  "kind": "aftk-knowledge-base",
  "nodesDir": "nodes",
  "internalDir": ".aftk"
}
```

### Proposed Lean-level type

```lean
namespace AFTK.KnowledgeBase

structure StorageManifest where
  schemaVersion : Nat := 1
  kind : String := "aftk-knowledge-base"
  nodesDir : String := "nodes"
  internalDir : String := ".aftk"

structure KnowledgeBaseStoragePaths where
  rootDir : System.FilePath
  manifestPath : System.FilePath
  nodesDir : System.FilePath
  internalDir : System.FilePath

end AFTK.KnowledgeBase
```

The manifest should stay small.
It is not meant to become a dump of global state.
Its job is to describe the storage root and make future schema/version transitions manageable.

## Canonical node area: `knowledgebase/nodes/`

All canonical node content should live under:

```text
knowledgebase/nodes/
```

This directory should contain only canonical node files arranged according to the node ID mapping.

### Rules for `knowledgebase/nodes/`

- files under `knowledgebase/nodes/` are canonical data
- node files must follow the `.md`/`.json` sibling pairing rule from `plans/knowledgebase/node.md`
- subdirectories exist only to realize the path mapping from node IDs
- the knowledge base should not require additional per-node sidecar directories in v1

## Internal derived area: `knowledgebase/.aftk/`

All generated, rebuildable, or operational files should live under:

```text
knowledgebase/.aftk/
```

The initial design reserves subdirectories such as:

- `knowledgebase/.aftk/index/` — search/index data
- `knowledgebase/.aftk/cache/` — caches
- `knowledgebase/.aftk/tmp/` — temporary files

### Rules for `knowledgebase/.aftk/`

- files under `knowledgebase/.aftk/` are not canonical
- they may be deleted and rebuilt from canonical storage
- higher layers should not treat them as the source of truth
- their exact internal formats may evolve more freely than canonical storage

This keeps advanced tooling possible without compromising the simplicity of the core storage model.

## Optional additional files

The storage design should allow a small number of additional human-oriented files at the root, such as:

- `knowledgebase/README.md`

However, canonical semantics in v1 should depend only on:

- `manifest.json`
- `nodes/`

Everything else should be optional unless explicitly added by a future storage-schema revision.

## Storage discovery policy

The canonical default location for the knowledge base should be:

```text
./knowledgebase
```

relative to the project root.

A later CLI design may allow explicit overrides, but the storage design should treat `./knowledgebase` as the default repository-local root.

The presence of `knowledgebase/manifest.json` should be the primary signal that a directory is an initialized knowledge-base root.

## Validation expectations

A storage validator should eventually be able to check at least the following:

- the knowledge-base root exists
- `manifest.json` exists and parses
- the manifest kind and schema version are supported
- `nodes/` exists
- `internalDir` may be created lazily if missing
- every canonical node file pair under `nodes/` satisfies the node invariants
- no canonical node data is stored under `.aftk/`
- the layout matches the manifest’s declared directory names

## Version-control expectations

The intended version-control policy for the storage design is:

### Track in git

- `knowledgebase/manifest.json`
- `knowledgebase/nodes/**`
- optional human documentation files such as `knowledgebase/README.md`

### Usually ignore in git

- `knowledgebase/.aftk/**`

This keeps the canonical knowledge base reviewable while preventing generated state from polluting commits.

## Operational semantics

### Initialize storage

Initializing a new knowledge base should create at least:

- `knowledgebase/`
- `knowledgebase/manifest.json`
- `knowledgebase/nodes/`
- `knowledgebase/.aftk/`

Subdirectories like `index/`, `cache/`, and `tmp/` may be created eagerly or lazily.

### Create or update a node

Node creation and update operations should modify files under `knowledgebase/nodes/` only for canonical content.
Derived data under `knowledgebase/.aftk/` may then be refreshed or invalidated as needed.

### Rebuild indexes

Search and indexing state should be rebuildable entirely from:

- `knowledgebase/manifest.json`
- `knowledgebase/nodes/**`

### Delete or rename nodes

Delete and rename operations should update canonical node files under `knowledgebase/nodes/` and then refresh derived state if necessary.

## Atomicity expectations

The first implementation should aim for practical filesystem safety:

- write updated canonical files using temp-file-plus-rename patterns where possible
- avoid leaving half-written JSON or Markdown files behind
- treat derived-state corruption as recoverable because derived state can be rebuilt

Cross-file atomicity for `.md` and `.json` pairs may not be perfect on every platform in v1, but operations should still be designed to minimize inconsistent intermediate states.

## Design decisions for v1

The initial storage design intentionally does **not** include:

- a database as canonical storage
- canonical search indexes
- a global monolithic JSON file containing all nodes
- content-addressed blob storage
- attachments or per-node asset directories in the base design
- distributed or remote-first storage semantics

Those may be explored later, but the first storage system should stay simple, local, and inspectable.

## Open questions for later refinement

- Should the manifest eventually include more global settings?
- Should node assets be added later, and if so, where should they live?
- How should storage-level repair remain coordinated with the broader repair design in `plans/knowledgebase/repair.md`?
- How should the on-disk index layout evolve alongside the broader indexing design in `plans/knowledgebase/indexing.md`?
- Should derived indexes eventually live outside `knowledgebase/` in some environments?
- How much configurability should the CLI expose for nondefault storage roots?

## Summary

The initial knowledge-base storage system should use a repository-local root at `knowledgebase/`.
Canonical data lives in:

- `knowledgebase/manifest.json`
- `knowledgebase/nodes/**`

Derived and rebuildable operational state lives in:

- `knowledgebase/.aftk/**`

Within `knowledgebase/nodes/`, each node is stored as a paired Markdown and JSON file according to the node-ID-to-path mapping defined in `plans/knowledgebase/node.md`.

This gives the rewrite a storage model that is simple, explicit, git-friendly, and ready for later Lean implementation.