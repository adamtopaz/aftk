# Knowledge Base Indexing Design

## Status

Design-only component plan for knowledge-base indexing.
This document refines the overall knowledge base plan in `plans/knowledgebase.md` and works together with `plans/knowledgebase/storage.md`, `plans/knowledgebase/search.md`, `plans/knowledgebase/validation.md`, `plans/knowledgebase/repair.md`, and `plans/knowledgebase/cli.md`.

## Component implementation status

- Overall status: Not implemented
- Implemented in code: No
- Last updated basis: design only

## Purpose

This document defines the indexing model for the knowledge base layer.
It explains what indexes are for, what they may contain, where they live, how they relate to canonical storage, how they are rebuilt, and how they interact with search, validation, and repair.

No code is being added yet.
This file is only a design target for later implementation.

## Design goals

Indexing should:

- accelerate search and graph-style queries without becoming canonical storage
- remain rebuildable from canonical files alone
- preserve the canonical semantics defined by direct file scanning
- support whole-knowledge-base operations such as incoming-relationship lookup
- be safe to delete and recreate
- remain optional in the first implementation slice

Lean module and namespace naming for this layer should use `KnowledgeBase` rather than `KB`.
The public CLI should use `lake exe aftk knowledgebase ...`.

## Core indexing principles

### 1. Indexes are derived, never canonical

Indexes exist only to improve performance and operational convenience.
They are not part of the source of truth.
The source of truth remains:

- `knowledgebase/manifest.json`
- canonical node Markdown files
- canonical node metadata JSON files

### 2. Direct scan defines semantics

If direct canonical scanning and an index ever disagree, the canonical scan wins.
Indexes should preserve the same intended semantics as nonindexed operations.

### 3. Indexes may be deleted at any time

The system should be correct even if the entire index directory is removed.
A missing or stale index should degrade performance, not correctness.

### 4. Indexing should be incremental-friendly, but not dependent on incrementality

The design should leave room for incremental updates later.
However, the first practical indexing strategy may simply rebuild from scratch.

## Relationship to storage

The storage design reserves derived-state space under:

```text
knowledgebase/.aftk/index/
```

This directory is the natural home for rebuildable indexes.
It should remain clearly separate from canonical storage.

## What indexing is for

The indexing layer should eventually support operations such as:

- faster text search
- faster tag or metadata filtering
- faster incoming-relationship lookup
- node listing and counting without rescanning the full tree for every operation
- future richer graph/query features

Indexing is therefore primarily a performance and convenience layer on top of the canonical knowledge base.

## Indexable information

The indexing layer may eventually derive and store information such as:

### 1. Node inventory

A list or table of known nodes, including:

- node ID
- canonical paths
- key metadata fields such as title, kind, status

### 2. Text search support

Derived search data based on:

- Markdown body text
- searchable metadata fields such as title and summary

### 3. Metadata lookup tables

Indexes keyed by fields such as:

- tags
- kind
- status
- author
- ID prefix

### 4. Relationship indexes

Derived graph-support data such as:

- outgoing edges by source
- incoming edges by target
- relationship edges grouped by kind

This is especially useful because incoming relationships are not explicitly stored canonically.

## Proposed directory layout

A reasonable initial indexing layout under the existing derived-state area is:

```text
knowledgebase/
  .aftk/
    index/
      manifest.json
      nodes.json
      text/
      metadata/
      relationships/
```

This is only a conceptual layout.
The exact file split can evolve.
The important design point is that index state lives under `knowledgebase/.aftk/index/` and remains clearly derived.

### Top-level meaning

- `knowledgebase/.aftk/index/manifest.json` — index schema/version and build metadata
- `knowledgebase/.aftk/index/nodes.json` — optional node inventory/index root
- `knowledgebase/.aftk/index/text/` — text-search-related derived state
- `knowledgebase/.aftk/index/metadata/` — field/filter lookup state
- `knowledgebase/.aftk/index/relationships/` — graph/incoming-edge lookup state

## Index manifest

The index area should have its own small manifest.
This helps make rebuild state explicit and versioned without mixing it into canonical storage.

### Proposed manifest shape

```json
{
  "schemaVersion": 1,
  "kind": "aftk-knowledge-base-index",
  "sourceSchemaVersion": 1
}
```

This manifest is derived state, not canonical storage.
It may include more build metadata later if useful.

### Proposed Lean-level type

```lean
namespace AFTK.KnowledgeBase

structure IndexManifest where
  schemaVersion : Nat := 1
  kind : String := "aftk-knowledge-base-index"
  sourceSchemaVersion : Nat := 1

structure IndexPaths where
  rootDir : System.FilePath
  manifestPath : System.FilePath
  nodesPath : System.FilePath
  textDir : System.FilePath
  metadataDir : System.FilePath
  relationshipsDir : System.FilePath

end AFTK.KnowledgeBase
```

## Index build modes

The design should support at least two build strategies.

### Full rebuild

A full rebuild scans canonical storage and recreates all index data.
This is the simplest and most trustworthy strategy.
It should be the baseline behavior.

### Incremental refresh

A later implementation may support partial updates after node mutations.
However, incrementality should be treated as an optimization, not as the only correct mode.

## Staleness model

Indexes may become stale when canonical content changes.
The design should assume this can happen.

### Acceptable responses to stale indexes

- ignore them and use direct scan mode
- rebuild them eagerly
- rebuild them lazily when an indexed operation runs
- report staleness through status/validation commands if detection is available

### What should not happen

A stale index should not silently redefine results in a way that conflicts with canonical content.
If freshness cannot be trusted, canonical scanning should remain available as a fallback.

## Freshness and invalidation

The first implementation does not need a sophisticated invalidation system.
Still, the design should leave room for mechanisms such as:

- rebuild-after-mutation in CLI commands
- timestamp-based staleness hints
- manifest-level build metadata
- future content-hash-based invalidation

For v1, a simple rule like “rebuild after explicit `reindex` or on demand” is sufficient.

## Interaction with search

Indexing and search are closely related, but not identical.

- search defines **what results mean**
- indexing defines **how results may be obtained efficiently**

The dedicated search design in `plans/knowledgebase/search.md` defines the search semantics.
This indexing design exists to support those semantics efficiently.

### Search with no index

The knowledge base should still support correct search by direct canonical scan.

### Search with an index

If an index is present and trusted, search may use it for speed.
But the results should match the intended canonical semantics.

## Interaction with relationships

Incoming relationship lookup is an especially good candidate for derived indexing.
Canonically, outgoing edges are stored in per-node metadata.
Incoming edges are derived.

That means an index may maintain structures such as:

- target node -> incoming relationship list
- relationship kind -> matching edges

This can significantly improve commands such as:

```text
lake exe aftk knowledgebase relationships incoming <id>
```

without changing the canonical relationship model.

## Interaction with validation

Validation should not fundamentally depend on indexes.
Still, indexing may interact with validation in useful ways.

### Index-aware validation possibilities

- detect obviously stale or malformed index state
- confirm that index manifests or directory layout are structurally sensible
- optionally compare index-derived counts to canonical scans

### Important constraint

Canonical validation must remain possible without any index.
An index may support extra checks, but it is not the truth source.

## Interaction with repair

Because indexes are derived, repair may treat them aggressively.
The dedicated repair design in `plans/knowledgebase/repair.md` already supports that philosophy.

Typical repair actions involving indexes may include:

- delete stale index files
- clear a corrupt index directory
- rebuild indexes from canonical storage

These are among the safest repair operations in the whole layer.

## CLI alignment

The existing CLI plan already mentions a deferred `reindex` command.
This indexing design clarifies what that should eventually mean.

### Candidate commands

#### `reindex`

```text
lake exe aftk knowledgebase reindex
```

Rebuild the derived index state from canonical storage.

#### `reindex --clear`

```text
lake exe aftk knowledgebase reindex --clear
```

Clear any existing index state first, then rebuild.

#### `status`

The existing `status` command may later report index-related information such as:

- whether an index exists
- whether an index manifest exists
- whether the index appears stale if such detection is implemented

### Search and relationships commands

Search and incoming-relationship commands may later use indexes opportunistically.
However, the CLI contract should not require callers to know or care whether an index or a direct scan was used.

## Output model

Commands that operate on indexes should still support both text and JSON output.
Useful output fields may include:

- whether a rebuild occurred
- how many nodes were scanned
- index paths written
- warnings about stale or missing index state

## Design decisions for v1

The first implementation of the knowledge base does **not** need a full indexing subsystem.
Indexing is intentionally designed as a later enhancement.

When indexing work does begin, v1 indexing should likely prioritize:

1. full rebuild only
2. optional node inventory support
3. optional incoming-relationship index support
4. optional text-search acceleration

The initial indexing design intentionally does **not** require:

- canonical reliance on indexes
- distributed indexing
- binary search-engine integration as the first step
- sophisticated incremental maintenance
- approximate or semantic retrieval indexes

## Recommended first implementation slice

Indexing should come after the first direct-scan search and validation implementations are working.
A sensible first indexing slice would likely be:

1. add index-path helpers under `knowledgebase/.aftk/index/`
2. add a small index manifest
3. implement `reindex` as a full rebuild
4. build an incoming-relationship index
5. optionally add lightweight text-search support

This would provide real operational value while keeping the semantic source of truth simple.

## Lean 4 reuse findings

The core `Std` collections already cover much of the intended indexing workload.

- `Std.HashMap` and `Std.HashSet` are good for fast accumulation during full rebuilds.
- `Std.TreeMap` and `Std.TreeSet` are especially attractive for persisted index data because they give deterministic key order and ordered queries.
- `Std.TreeMap` already exposes `minKey?`, `maxKey?`, `getEntryGE?`, `getEntryGT?`, `getEntryLE?`, and `getEntryLT?`, which are useful for prefix and range-style index queries later.
- `Lean.Data.Json.FromToJson.Extra` already provides `ToJson` and `FromJson` instances for `Std.TreeMap String α`, which can reduce boilerplate if string-keyed index files are stored as JSON objects.
- `Array.qsort` remains a simple fallback for deterministic arrays if an index is accumulated in hash-based structures first and only sorted at write time.
- `IO.FS.Metadata.modified` and related timestamp APIs are available if the index manifest later wants cheap staleness hints.
- If stable insertion-order dedup becomes useful, the bundled `Lake.Util.OrdHashSet` is a small optional reference implementation worth considering.

## Open questions for later refinement

- Should node inventory indexing be split from search indexing, or combined under one manifest?
- How much staleness detection should be built into v1 indexing?
- Should `reindex` rebuild everything always, or later support narrower scopes?
- What exact internal formats should text and relationship indexes use?
- Should index status become part of validation, status, or both?

## Summary

The indexing layer should live entirely under derived state in:

- `knowledgebase/.aftk/index/`

It should accelerate search, metadata filtering, and especially derived relationship queries such as incoming-edge lookup, while remaining fully rebuildable from canonical knowledge-base files.

Indexes are optional, noncanonical, and disposable.
They exist to improve performance and convenience, not to redefine the meaning of knowledge-base operations.