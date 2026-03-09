# Knowledge Base Layer Plan

## Status

Overall design/status document for the first layer of `aftk`.
This file now mainly records the rationale and follow-on roadmap for a largely implemented layer.
Detailed subdesigns live under `plans/knowledgebase/`, while current implementation behavior is documented under `docs/knowledgebase/`.

## Plan implementation status

- Overall status: Partially implemented, with the core v1 knowledge-base layer landed in code
- Fully implemented: No
- Last updated basis: implemented types, storage, serialization, CLI, validation, search, relationship traversal, `lake test` coverage, and implementation docs under `docs/knowledgebase/`; indexing and repair remain deferred

This section is the authoritative status summary for this layer.
Historical comparison and design-rationale sections below remain useful, but `docs/knowledgebase/**` is the source of truth for current implementation behavior.

## Purpose

The knowledge base layer is the foundation of the new architecture.
Its job is to store, organize, retrieve, and search natural-language mathematical and technical knowledge.

The most important architectural commitment of AFTK is:

> The knowledge base is the single source of truth for natural-language knowledge.

Higher layers may reference, elaborate, transform, or act on that knowledge, but they should not introduce competing natural-language storage systems.

## Position in the layered architecture

The overall architecture stack is:

1. Knowledge base layer
2. Informal layer
3. Server and file-worker layer
4. Toolkit layer
5. AI autoformalization agent layer

The knowledge base layer sits at the bottom of this stack.
Everything above it depends on it directly or indirectly.

## Core responsibilities

The knowledge base layer should provide the following capabilities:

- create natural-language knowledge entries
- read and inspect existing entries
- modify existing entries
- attach and maintain structured metadata
- represent relationships between knowledge-base nodes
- search across the corpus
- support querying and filtering over metadata, content, and relationships
- provide stable references that higher layers can depend on
- expose these capabilities through Lean-native tooling

This layer is not just a passive file store.
It is the system boundary for managing natural-language knowledge in a structured, queryable way.

## Architectural commitments

### 1. Single source of truth for natural-language content

Natural-language knowledge should live in exactly one place in the system: the knowledge base.

This means, for example, that the later informal layer should refer to knowledge-base nodes rather than storing separate copies of the same prose.

### 2. Human-readable primary content

Main content should be stored in Markdown.
This keeps the core knowledge easy to read, review, diff, and edit by humans.

### 3. Machine-readable structured metadata

Metadata should be stored in JSON.
This gives higher layers and automation tools a reliable format for structured inspection, filtering, validation, and indexing.

### 4. Relationship-aware metadata

Knowledge-base metadata should support explicit relationships between nodes.
That allows the layer to represent cross-references, dependencies, refinement links, examples, prerequisites, and other semantic connections in a structured way.

This does not require the first implementation to be a full graph database.
However, the metadata model should be designed so that the knowledge base can naturally be treated as a knowledge graph when needed.

### 5. Lean-native core interface

The primary interface to the knowledge base should be a Lean-based CLI:

```text
lake exe aftk knowledgebase ...
```

This keeps the core of the system Lean-native and ensures that the knowledge base integrates cleanly with the rest of the lower-level architecture.

Lean module and namespace naming for this layer should likewise use `KnowledgeBase` rather than the abbreviation `KB`.

### 6. File-backed and inspectable storage

The knowledge base should remain transparent and inspectable at the filesystem level.
Even when richer indexing or search infrastructure is added later, the canonical representation should remain understandable and editable in ordinary files.

## Conceptual model

The central object in this layer is a **knowledge-base node**.

A node represents one unit of natural-language knowledge, such as:

- a definition
- a theorem statement in informal form
- an explanation
- a proof sketch
- a concept note
- a worked example
- a technical note
- a cross-referenceable documentation unit

At a high level, each node should have:

- an identity
- Markdown content
- JSON metadata
- zero or more relationships to other nodes, represented through metadata

The conceptual split is already clear:

- **Markdown** holds the main human-facing content
- **JSON** holds structured metadata about that content

The node-level pairing and naming design is captured in `plans/knowledgebase/node.md`.
The broader storage layout is captured in `plans/knowledgebase/storage.md`.

## Component plans

The following component plans refine parts of the knowledge base layer design:

- `plans/knowledgebase/metadata.md` — initial Lean metadata type design and JSON representation
- `plans/knowledgebase/node.md` — node identity, Markdown/JSON pairing, and node-level invariants
- `plans/knowledgebase/storage.md` — repository-level storage layout, manifest, and canonical-vs-derived storage rules
- `plans/knowledgebase/layout.md` — Lean library/module layout, dependency boundaries, and CLI-vs-library split
- `plans/knowledgebase/testing.md` — test strategy, fixture layout, CLI integration coverage, and regression-test scope
- `plans/knowledgebase/cli.md` — CLI command structure, command families, output model, and error behavior
- `plans/knowledgebase/validation.md` — validation scopes, issue model, and CLI-facing validation behavior
- `plans/knowledgebase/search.md` — search semantics, result model, and index strategy
- `plans/knowledgebase/serialization.md` — canonical JSON/Markdown serialization rules and CLI JSON output design
- `plans/knowledgebase/repair.md` — validation-driven repair strategy, quarantine behavior, and repair CLI design
- `plans/knowledgebase/indexing.md` — derived index layout, rebuild semantics, and index/search integration

Likely future component plans include:

- none currently identified beyond refinements to the existing component plans

## Primary operations

The knowledge base CLI should eventually support operations in categories like these:

### Content management

- create a node
- update a node’s body or metadata
- rename or move a node
- delete a node if deletion is supported
- view a node
- list nodes

### Metadata management

- inspect metadata
- edit metadata
- validate metadata
- query by metadata fields

### Discovery

- full-text search
- tag/category search
- related-node traversal
- listing/filtering/sorting operations

### Integrity and maintenance

- validation of node structure
- detection of broken references
- indexing or reindexing support
- consistency checks between content and metadata

## Relationship to higher layers

The knowledge base layer should be designed so that higher layers can rely on it without reimplementing its logic.

### Informal layer

The informal layer should reference knowledge-base nodes directly.
For example, a construct like `informal[a.b.c]` should resolve through the knowledge base rather than through a separate informal-content store.

### Server and file-worker layer

The server and file-worker should be able to inspect and operate on knowledge-base content as part of their broader service role.

### Toolkit and AI agent layers

TypeScript tools and AI agents should consume stable knowledge-base operations through the lower-level interfaces, rather than bypassing the layer with ad hoc file conventions.

## Boundaries and non-goals

The knowledge base layer is foundational, but it should still have a clear scope.

### In scope

- canonical storage of natural-language knowledge
- structured metadata
- querying and search
- CLI-driven management of knowledge nodes
- stable references for other layers

### Out of scope for this layer

- Lean elaboration behavior itself
- `informal[...]` semantics beyond the fact that they reference KB nodes
- server orchestration concerns
- TypeScript toolkit abstractions
- AI-agent workflow logic

Those belong to later layers.

## Design constraints

As more detailed designs are written, the knowledge base layer should preserve the following constraints:

- canonical data should stay file-backed
- content should remain easy for humans to edit directly
- metadata should remain predictable for programs to consume
- node identities should be stable enough for references from other layers
- the interface should be suitable for automation as well as manual use
- the design should support growth into search, indexing, and agent workflows

## Questions to refine in follow-up component plans

This overview leaves several important questions open for later design documents:

- What metadata fields are required, optional, or derived beyond the initial metadata type?
- How should links and references between nodes be represented at the filesystem and CLI levels beyond the basic node model?
- What operations should be atomic from the CLI’s point of view?
- What parts of the implementation should be pure Lean, and what parts may rely on supporting libraries or tools?

## Lean 4 core and bundled-library reuse strategy

Research against the Lean 4 v4.28.0 sources bundled under:

```text
/home/dev/.elan/toolchains/leanprover--lean4---v4.28.0/src/lean
```

suggests that the first implementation should reuse existing Lean and bundled Lake infrastructure aggressively instead of introducing custom plumbing too early.

The most important reusable pieces are:

- `System.FilePath` and `IO.FS` for path computation, directory traversal, UTF-8 file IO, temp files, renames, and directory creation
- `Lean.Data.Json` plus `Lean.Data.Json.FromToJson` for JSON parsing, pretty-printing, and derived `ToJson`/`FromJson` instances
- `Std.HashMap` and `Std.HashSet` for accumulation, deduplication, and duplicate detection during scans
- `Std.TreeMap` and `Std.TreeSet` for deterministic ordering, persisted index structures, and ordered queries
- `Std.Time` for timestamp acquisition, parsing, and formatting support
- bundled Lake utilities such as `Lake.Util.Cli`, `Lake.Util.MainM`, and `Lake.Util.Log` if importing Lake modules into the executable target is acceptable

The component plans below now record file-specific reuse findings so implementation can start from the existing Lean toolchain rather than from fresh utility code.

## Remaining design work before implementation

The core knowledge-base architecture is now defined well enough that no additional large component plan is strictly required before beginning implementation.
However, a small amount of remaining design work should still be tracked explicitly so that implementation does not begin with avoidable ambiguity.

### Additional design docs to consider

These are likely useful follow-up documents, but they are not all blockers for the first implementation slice:

- none currently identified as missing design docs

### Design clarifications resolved for the first implementation

The previously identified blocking clarifications have now been resolved in the component plans:

- [x] Root discovery semantics fixed in `plans/knowledgebase/storage.md` and `plans/knowledgebase/cli.md`
- [x] Creation and mutation defaults fixed in `plans/knowledgebase/node.md`, `plans/knowledgebase/metadata.md`, and `plans/knowledgebase/cli.md`
- [x] Metadata replacement identity rule fixed in `plans/knowledgebase/metadata.md` and `plans/knowledgebase/cli.md`
- [x] Search v1 semantics fixed in `plans/knowledgebase/search.md` and `plans/knowledgebase/cli.md`
- [x] Validation severity policy fixed in `plans/knowledgebase/validation.md`
- [x] Mutation command model reconciled in `plans/knowledgebase/cli.md` and this overview plan
- [x] Stale resolved questions cleaned up where they were blocking implementation

At this point, no additional blocking design clarification is identified before starting implementation.

## Detailed phased implementation plan

Implementation should proceed bottom-up from reusable library modules to the CLI surface and then to cross-node services.
The key sequencing rule should be:

- get canonical types, paths, serialization, and storage operations correct first
- build the initial CLI on top of those library APIs rather than mixing parsing and file manipulation together
- implement validation and direct-scan discovery before adding derived indexes or repair automation

This order matches the component plans and keeps correctness anchored in canonical files throughout the first implementation.

### Phase 0 — establish the test harness and fixture strategy

Purpose:

- make testing part of the implementation from the beginning rather than a late cleanup task
- ensure later phases can land with coverage instead of accumulating untested behavior

Main work:

- add a dedicated knowledge-base test target, such as a small `lake exe` test runner
- add a project-local test harness with basic assertion helpers and grouped test execution
- choose the initial test-module layout under `AFTKTest/KnowledgeBase/`
- add fixture and golden-data directories such as `tests/knowledgebase/fixtures/` and `tests/knowledgebase/golden/`
- add temporary-directory helpers so storage tests never mutate repository working files directly
- define the first fixture roots for:
  - empty or minimal valid roots
  - single-node valid roots
  - malformed manifest/metadata cases
  - orphan file cases
  - broken-relationship cases

Exit criteria:

- there is a runnable knowledge-base test target
- the project has a clear place for fixtures and golden files
- later phases can add tests incrementally without redesigning the harness

### Phase 1 — establish the module skeleton and dependency boundaries

Purpose:

- replace the current placeholder library layout with the intended `AFTK/KnowledgeBase/` structure
- make the CLI/library split real before implementation logic spreads across ad hoc files

Main work:

- add `AFTK/KnowledgeBase.lean` as the public library root
- add initial modules such as:
  - `AFTK/KnowledgeBase/Types.lean`
  - `AFTK/KnowledgeBase/PathLayout.lean`
  - `AFTK/KnowledgeBase/Serialization.lean`
  - `AFTK/KnowledgeBase/Storage.lean`
  - `AFTK/KnowledgeBase/Validation.lean`
  - `AFTK/KnowledgeBase/Search.lean`
  - `AFTK/KnowledgeBase/Repair.lean`
  - `AFTK/KnowledgeBase/Indexing.lean`
  - `AFTK/KnowledgeBase/Cli/Types.lean`
  - `AFTK/KnowledgeBase/Cli/Parse.lean`
  - `AFTK/KnowledgeBase/Cli/Render.lean`
  - `AFTK/KnowledgeBase/Cli/Main.lean`
- update `AFTK.lean` so it re-exports the reusable knowledge-base library rather than a placeholder module
- update `Main.lean` so it becomes a thin executable entrypoint and top-level dispatcher
- decide early whether `Lake.Util.Cli`, `Lake.Util.MainM`, and `Lake.Util.Log` will be used directly, and if so, confine them to `Cli/*`

Exit criteria:

- the project builds with the intended knowledge-base module tree in place
- the executable has a clear knowledge-base entrypoint, even if most commands are still stubs
- the dependency direction from `plans/knowledgebase/layout.md` is reflected in the source tree

### Phase 2 — implement foundational domain types and path/layout helpers

Purpose:

- stabilize the low-level types and path rules that all later phases depend on

Main work:

- implement foundational types from the node and metadata plans, including:
  - `NodeId`
  - `Timestamp`
  - `NodeKind`
  - `NodeStatus`
  - `RelationshipKind`
  - `Relationship`
  - `LeanDeclRef`
  - `NodeMetadata`
  - `Node`
  - `NodePaths`
  - `StoredNode`
  - `StorageManifest`
  - storage-path records such as `KnowledgeBaseStoragePaths`
- implement `NodeId` validation according to the dotted-segment naming rules from `plans/knowledgebase/node.md`
- implement path/layout helpers for:
  - root resolution
  - manifest path resolution
  - node ID to relative path-stem conversion
  - canonical `.md` / `.json` sibling path computation
  - path-derived ID reconstruction where needed for validation
- keep these modules free of CLI parsing and high-level search/repair behavior

Exit criteria:

- the library exposes stable low-level knowledge-base types
- canonical examples such as `topology.open_cover` round-trip cleanly through the path mapping helpers
- later modules can depend on these types without importing CLI code

### Phase 3 — implement canonical serialization and storage primitives

Purpose:

- make canonical filesystem operations correct before building the user-facing CLI

Main work:

- implement strict manifest parsing and writing
- implement strict metadata parsing and writing, including:
  - unknown-field rejection
  - required-field checks
  - default/optional-field handling
  - deterministic canonical output
- decide explicitly whether canonical object ordering will follow sorted `Lean.Json` output or a tiny custom writer for the plan’s preferred field order
- implement `NodeId` and `Timestamp` JSON/string wrappers
- implement Markdown read/write helpers with UTF-8 and newline normalization rules
- implement storage primitives for:
  - `init`-style root creation
  - manifest load/save
  - node load/save
  - canonical node enumeration by explicit directory recursion
  - conflict-safe file writes using temp-file-plus-rename patterns where possible
- implement library-level mutation helpers for create, body replace, metadata replace, rename, and delete, even if some CLI commands remain deferred until later phases

Exit criteria:

- the library can initialize a root, read and write the manifest, and read and write nodes through a reusable API
- canonical JSON output is deterministic and matches the serialization plan closely enough for diffs/tests to be stable
- node enumeration works from canonical storage alone without relying on derived state

### Phase 4 — implement the initial CLI MVP for root and node management

Purpose:

- expose the first usable public command surface on top of the storage library

Main work:

- implement global CLI option handling for `--root`, `--format`, and `--help`
- implement parser, dispatcher, and text/JSON renderers
- implement the first command slice from `plans/knowledgebase/cli.md`:
  - `init`
  - `status`
  - `list`
  - `show`
  - `create`
  - `body show`
  - `body set`
  - `metadata show`
  - `metadata replace`
- enforce the already-resolved operational rules during command handling:
  - no lazy initialization outside `init`
  - `create` populates `createdAt` and `updatedAt`
  - body mutation refreshes `updatedAt`
  - metadata replacement refreshes `updatedAt`
  - metadata replacement must not change the node ID
- implement the stable CLI JSON envelope described in `plans/knowledgebase/serialization.md`
- implement explicit, consistent exit-code handling for usage errors, not-found errors, validation failures, and conflicts

Exit criteria:

- `lake exe aftk knowledgebase ...` is usable for happy-path storage and node-management workflows
- both text and JSON output modes work for the initial command slice
- the CLI remains a thin layer over reusable library code rather than embedding file-layout logic directly

### Phase 5 — implement validation and integrity reporting

Purpose:

- make canonical integrity checking available before richer discovery and maintenance features are added

Main work:

- implement structured validation types:
  - `ValidationSeverity`
  - `ValidationScope`
  - `ValidationIssue`
  - `ValidationReport`
- implement stable validation issue codes for storage, node, metadata, and relationship failures
- implement validators for:
  - storage roots and manifests
  - per-node pairing and ID/path invariants
  - metadata schema and field constraints
  - whole-knowledge-base duplicate-ID and broken-target detection
- expose validation commands:
  - `validate storage`
  - `metadata validate <id>`
  - `validate node <id>`
  - `validate all`
- integrate validation results into text output, JSON output, and exit-code behavior

Exit criteria:

- the CLI can produce structured validation reports suitable for humans, automation, and CI-style checks
- canonical problems surface as explicit issue codes instead of opaque generic failures
- whole-knowledge-base validation works directly from canonical files, without requiring indexes

### Phase 6 — implement direct-scan search and relationship discovery

Purpose:

- provide the first discovery/query features while keeping semantics defined by canonical storage

Main work:

- implement the initial search request/result types
- implement direct-scan `search text <query>` using case-insensitive substring matching over:
  - Markdown body text
  - metadata `title`
  - metadata `summary`
- implement direct-scan `search tag <tag>` using exact tag matching
- ensure deterministic node-ID ordering and optional result limits
- implement relationship-oriented commands over canonical metadata:
  - `relationships outgoing <id>`
  - `relationships incoming <id>`
  - `relationships related <id>` as a convenience view if feasible
- if `list` filtering is not already complete in Phase 4, add the first lightweight filters here (`--prefix`, `--kind`, `--status`, `--tag`)

Exit criteria:

- discovery commands work correctly without any derived index state
- relationship-aware queries are available directly from node metadata
- search output is structured enough for both interactive use and automation

### Phase 7 — complete the v1 mutation surface and harden integration boundaries

Purpose:

- finish the remaining core node-management operations and stabilize the layer for higher-level consumers

Main work:

- implement `rename` and `delete`
- ensure rename updates metadata ID and canonical paths together as one logical operation
- ensure conflict handling is clear for rename/create/delete cases
- harden operational behavior around not-found, already-exists, malformed metadata, and path/ID mismatch cases
- stabilize the reusable public import surface of `AFTK.KnowledgeBase`
- document the assumptions this layer exposes to the later informal layer and server/file-worker layer

Exit criteria:

- the knowledge-base layer supports the full initial node lifecycle
- higher layers can treat node IDs and canonical storage operations as stable interfaces
- the top-level plan’s definition of “first usable knowledge-base layer” is substantially satisfied

### Phase 8 — add optional derived indexing after direct-scan correctness is in place

Purpose:

- improve performance without changing semantics or introducing canonical dependence on indexes

Main work:

- add index-path helpers under `knowledgebase/.aftk/index/`
- add an index manifest and index path records
- implement `reindex` as a full rebuild
- build the first high-value derived indexes, especially:
  - node inventory support
  - incoming-relationship lookup support
- optionally add lightweight text-search acceleration only after the direct-scan search path is trusted
- surface index existence/staleness information through `status` and possibly validation later

Exit criteria:

- derived indexes can be deleted and rebuilt freely without affecting correctness
- indexed operations preserve the same results as canonical direct scans
- incoming-relationship queries no longer require a full scan when an index is available

### Phase 9 — add conservative repair and normalization tooling

Purpose:

- provide operational recovery tools only after validation and canonical write paths are already trustworthy

Main work:

- implement repair-plan data structures and CLI plumbing for a deferred `repair` command family
- start with the safest repair actions:
  - create missing internal directories
  - clear/rebuild derived state under `.aftk/`
  - normalize manifest formatting when the manifest already parses successfully
  - normalize metadata formatting for already-valid nodes
- add quarantine-backed handling of orphan canonical files with explicit confirmation
- keep ambiguous cases strategy-driven rather than automatic, especially:
  - metadata ID vs path ID mismatch
  - duplicate node IDs
  - unparseable metadata requiring semantic guesswork

Exit criteria:

- common nonsemantic integrity problems can be repaired conservatively
- repair does not silently destroy canonical content
- validation and repair form a coherent operational workflow

### Cross-phase implementation rules

The following rules should hold across all phases:

- keep CLI-only dependencies such as `Lake.Util.Cli` confined to `AFTK/KnowledgeBase/Cli/*`
- add or update tests in the same phase that introduces behavior rather than deferring all coverage to the end
- keep canonical JSON strict and deterministic from the beginning rather than treating that as later cleanup
- prefer direct canonical scans before adding derived indexing or cache-dependent behavior
- use validation reports and issue codes as the basis for later repair logic rather than inventing separate ad hoc diagnostics
- land each phase in a buildable state so the library and CLI can be smoke-tested incrementally
- treat `knowledgebase/manifest.json` and `knowledgebase/nodes/**` as the truth source throughout implementation

This phased plan should make it possible to land the knowledge-base layer in small, reviewable increments while preserving the architectural constraints set by the component designs.

## Implementation progress

This section tracks implementation progress for the knowledge base layer plan.
It should be updated as design decisions are made and code lands.

### Planning and design

- [x] Create the overall knowledge base layer plan
- [x] Define the knowledge-base directory and file layout (`plans/knowledgebase/storage.md`)
- [x] Define the Lean library/module layout for the knowledge-base layer (`plans/knowledgebase/layout.md`)
- [x] Define the knowledge-base testing strategy (`plans/knowledgebase/testing.md`)
- [x] Define node identity and naming conventions (`plans/knowledgebase/node.md`)
- [x] Define the initial Markdown + JSON pairing model (`plans/knowledgebase/node.md`)
- [x] Define the initial metadata schema (`plans/knowledgebase/metadata.md`)
- [x] Define how node-to-node relationships are represented in metadata (`plans/knowledgebase/metadata.md`)
- [x] Add a follow-up component plan for CLI design (`plans/knowledgebase/cli.md`)
- [x] Add a follow-up component plan for validation design (`plans/knowledgebase/validation.md`)
- [x] Add a follow-up component plan for search design (`plans/knowledgebase/search.md`)
- [x] Add a follow-up component plan for serialization design (`plans/knowledgebase/serialization.md`)
- [x] Add a follow-up component plan for repair design (`plans/knowledgebase/repair.md`)
- [x] Add a follow-up component plan for indexing design (`plans/knowledgebase/indexing.md`)
- [x] Research reusable Lean 4 core and bundled Lake support for implementation and record the findings across the component plans
- [x] Add a detailed phased implementation plan to this overview document

### Lean CLI surface

- [x] Add the top-level `lake exe aftk knowledgebase ...` command entry point
- [x] Define the initial subcommand structure (`plans/knowledgebase/cli.md`)
- [x] Implement `create`
- [x] Implement `read`/`show`
- [x] Implement `list`
- [x] Implement body mutation commands
- [x] Implement metadata inspection/replacement commands

### Validation and discovery

- [x] Implement metadata validation
- [x] Implement node structure validation
- [x] Implement basic full-text search
- [x] Implement metadata-based query/filter support
- [x] Implement relationship traversal/query support
- [x] Implement broken-reference detection

### Testing and hardening

- [x] Add a dedicated knowledge-base test target/harness
- [x] Add unit tests for `NodeId`, path/layout mapping, and canonical path derivation
- [x] Add serialization tests for strict manifest/metadata parsing and deterministic writing
- [x] Add temporary-directory storage tests for init/create/load/body/metadata flows
- [x] Add CLI integration tests for the initial command slice
- [ ] Add regression fixtures for malformed roots, orphan files, path/ID mismatches, and broken relationships

### Integration readiness

- [x] Provide stable node references for higher layers
- [x] Document assumptions needed by the informal layer
- [x] Document assumptions needed by the server/file-worker layer

### Notes

- Current state: core knowledgebase library, CLI, validation, search, relationship traversal, and test driver are implemented
- Canonical storage lives under `knowledgebase/manifest.json` and `knowledgebase/nodes/**`
- The public CLI surface is available at `lake exe aftk knowledgebase ...`
- Tests now run through `lake test`
- Implementation-facing docs now live under `docs/knowledgebase/`
- Repair and indexing remain intentionally deferred, with no dedicated code currently landed for them
- A larger malformed-root regression-fixture suite is still pending
- This checklist is intentionally high-level and can be refined further as the implementation grows

## Summary

The knowledge base layer is the foundational data layer of the `aftk` codebase.
It owns all natural-language knowledge in the system, stores main content in Markdown, stores structured metadata in JSON, and exposes Lean-native CLI operations for creating, editing, querying, and searching that knowledge.

Everything built later in AFTK should treat this layer as the canonical source of natural-language information.