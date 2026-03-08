# Informal Bridge-State Design

## Status

Component plan and implementation-status document for informal-layer bridge state.
This document refines the overall informal-layer plan in `plans/informal.md` and works together with `plans/informal/references.md`, `plans/informal/tracking.md`, `plans/informal/dependencies.md`, `plans/informal/presentation.md`, `plans/informal/layout.md`, and the knowledge-base plans under `plans/knowledgebase/`.

## Component implementation status

- Overall status: Not implemented
- Implemented in code: No
- Last updated basis: rewrite worktree has no dedicated bridge-state module or filesystem state yet; this design is based on `plans/informal.md` and the already-added informal component plans

## Purpose

This document defines what state belongs to the informal layer, what state belongs to the knowledge base, what state belongs to Lean source itself, and what state should remain purely derived or process-local.

Its main job is to prevent the rewrite from accidentally rebuilding the old architecture where the informal layer became a second natural-language store.

The most important rule is:

> The informal layer is a bridge layer, not a second content repository.

So this document is primarily about ownership boundaries:

- what the knowledge base owns canonically
- what Lean source owns canonically
- what the informal layer may persist as bridge-specific state
- what the informal layer may derive transiently
- and what the informal layer must not duplicate

## Design goals

The bridge-state design should:

- keep the knowledge base as the sole canonical owner of natural-language node content and metadata
- keep Lean source as the sole canonical owner of where `informal[...]` appears in code
- allow the informal layer to persist only the minimal bridge-specific state it truly owns
- keep derived indexes and caches clearly noncanonical
- avoid duplicate workflow metadata, duplicate node bodies, and duplicate path conventions
- make later server/file-worker and CLI behavior easy to reason about
- stay compatible with the declaration-level public tracking model

## Scope and non-scope

### In scope

- ownership boundaries between Lean source, the knowledge base, and the informal layer
- persistent bridge-specific state in the informal layer
- derived bridge-local indexes and caches
- non-duplication rules for metadata and workflow state
- interaction between knowledge-base `leanRefs` and informal-layer tracking
- recommendations for where any future noncanonical bridge-local filesystem state should live

### Out of scope

- the detailed reference type itself
- the placeholder primitive
- detailed dependency algorithms
- detailed presentation formatting
- CLI command syntax
- higher-layer workflow/orchestration state

Those are covered by companion plans.

## Core ownership model

The rewrite should treat the full system state as divided into four main categories.

### 1. Lean source canonical state

Lean source files canonically own:

- the actual occurrences of `informal[...]` in declarations and proofs
- the enclosing declaration structure those occurrences live inside
- the surrounding formal code that depends on or replaces those occurrences

This means the informal layer should not try to store a second authored record of where `informal[...]` appears.
That information is authored in `.lean` files.

### 2. Knowledge-base canonical state

The knowledge base canonically owns:

- node ids
- Markdown bodies
- node metadata
- node relationships
- tags/authors/summary/title and similar descriptive metadata
- any node-level workflow state the project chooses to place in knowledge-base metadata
- any canonical Lean-reference metadata that belongs to the node model

This means the informal layer should not create a second canonical store for:

- informal notes
- node metadata
- status values
- tags
- relationships
- source refs
- issue lists
- parent links
- or similar node-attached content/workflow data

### 3. Informal-layer persistent bridge state

The informal layer may persist bridge-specific state that is not otherwise owned canonically.
In v1, that should be extremely small.

The main example is:

- declaration-level declaration↔reference linkage recorded through the persistent environment extension

### 4. Informal-layer derived or transient state

The informal layer may also compute or cache transient views such as:

- reverse reference->declaration lookup
- declaration dependency indexes
- projected reference dependency indexes
- compact presentation summaries
- richer presentation payloads
- imported environment caches in the CLI
- knowledge-base resolution contexts or memoized lookups

These are not canonical authored state.
They are derived conveniences.

## Canonical state the informal layer does **not** own

To make the ownership boundary explicit, the informal layer should not canonically own any of the following.

### Natural-language content

The informal layer should not own:

- Markdown note bodies
- prose summaries
- freeform note text
- copied theorem statements or proof sketches

All of that belongs in knowledge-base nodes.

### Node metadata

The informal layer should not define a second metadata schema for referenced nodes.
In particular, it should not canonically own its own copies of:

- `title`
- `summary`
- `kind`
- `status`
- `tags`
- `authors`
- `relationships`
- `leanRefs`
- timestamps
- source/provenance metadata attached to nodes

If the informal layer needs these values, it should read them from the resolved knowledge-base node.

### Node identity/path rules

The informal layer should not own:

- a second id type for natural-language nodes
- a second path mapping scheme like `informal/...`
- per-reference methods such as `markdownPath` or `metadataPath`

Those were features of the old sidecar-based design and should not return.

### Workflow orchestration state

The informal layer should not own higher-level orchestration state such as:

- readiness classifications
- scheduling priorities
- source-gap diagnoses
- full active-frontier state
- orchestration attempt history

Those belong to higher layers.

## What persistent bridge state the informal layer *does* own

The informal layer should own only state that is genuinely about the bridge between Lean code and knowledge-base nodes.

## V1 persistent bridge state

The core v1 persistent bridge state is:

- a declaration-level mapping from Lean declaration names to sets of `InformalReference`s

This is the state recorded by the tracking layer’s persistent environment extension.

### Why this state belongs here

Neither Lean source alone nor the knowledge base alone owns the compiled, declaration-level queryable linkage in this form.
It is a bridge artifact derived from successful elaboration and useful for later tooling.

### Why this state should remain small

This state should only record:

- which declarations successfully reference which node ids

It should not expand into a shadow knowledge graph or shadow metadata store.

## What should be persisted in the environment extension

The extension should persist only stable declaration↔reference linkage.
That means:

- declaration names
- validated `InformalReference` values
- set semantics rather than multiplicity counts

It should **not** persist:

- resolved node snapshots
- node bodies
- copied metadata fields
- source positions as public state
- placeholder tags as public state
- dependency indexes
- presentation payloads

## Why placeholder tags are not bridge state

Placeholder tags are important for term distinctness, but they are not part of the public persistent bridge-state model.
They are elaboration-level term identity markers.

Persisting them as bridge state would:

- pull the design toward a per-site public API
- duplicate information not needed for declaration-level queries
- confuse placeholder identity with declaration↔reference linkage

So placeholder tags should remain elaboration-local or term-local, not canonical bridge state.

## Why resolved nodes are not bridge state

Resolved nodes should not be persisted as informal-layer state.
They are snapshots of knowledge-base content.

Persisting them would:

- duplicate knowledge-base canonical content
- risk staleness against the canonical files
- tie bridge state too tightly to a particular root/filesystem snapshot

If a consumer needs node data, it should resolve the tracked reference through the knowledge-base layer when needed.

## Derived bridge-local state

Beyond the persistent declaration↔reference linkage, the informal layer may compute richer derived state.
This should be treated as disposable and rebuildable.

## Declaration/reference indexes

Derived indexes may include:

- reverse reference->declaration lookup
- declaration-count summaries
- unique-reference inventories

These should be computed from the persistent tracking state rather than separately authored.

## Dependency views

Derived dependency state may include:

- declaration dependency indexes
- reference dependency indexes
- dependency leaves

These are derived from:

- Lean environment information
- the persistent tracking state

They should not become separately authored canonical bridge data in v1.

## Presentation state

Derived presentation state may include:

- compact summaries
- rich presentation payloads
- body previews
- rendered text blocks

These are derived from resolved knowledge-base nodes and should not be stored as canonical bridge data.

## Process-local caches

The informal layer may eventually use process-local caches for performance.
Possible examples include:

- cached imported Lean environments in the CLI
- cached knowledge-base root contexts
- cached presentation payloads keyed by node id and render mode

### Rules for process-local caches

- they must be disposable
- correctness must not depend on them
- stale cache state must not redefine canonical behavior
- they should not be exposed as user-facing persistent state

## Filesystem-backed noncanonical bridge state

The v1 recommendation is conservative:

- do **not** introduce a new persistent filesystem bridge-state area just for the informal layer
- rely on Lean’s environment extension persistence plus process-local caches where needed

That keeps the first implementation simple and avoids prematurely inventing a second derived-state layout.

## If future persisted bridge-local caches/indexes are needed

If later experience shows that some bridge-local derived state really should be persisted outside `.olean` files, it should:

- remain clearly noncanonical
- live under the existing knowledge-base derived-state area rather than under a new `informal/` root

Reasonable future homes would be subdirectories under:

```text
knowledgebase/.aftk/
```

such as an informal-specific cache or index subdirectory.

### What should never happen

The rewrite should not reintroduce a top-level authored tree like:

```text
informal/
```

as a second natural-language or workflow-state store.

## Relationship to knowledge-base `leanRefs`

One subtle boundary deserves special attention.
The knowledge-base metadata model already includes `leanRefs`.
The informal layer also tracks declaration↔reference linkage.
These are related but not the same thing.

## Meaning of knowledge-base `leanRefs`

Knowledge-base `leanRefs` are canonical node metadata.
They are authored or maintained as part of the node.
Conceptually, they mean things like:

- this knowledge-base node is associated with these Lean declarations
- this node is relevant to or elaborated by these declarations

They belong to the node’s canonical metadata model.

## Meaning of informal-layer tracking

Informal-layer tracking means:

- these Lean declarations currently contain successful `informal[...]` occurrences referencing these node ids

This is a compiled bridge view of current source usage, not node-authored metadata.

## Important rule

The rewrite should not silently conflate these two mechanisms.
In particular:

- tracking should not automatically rewrite `leanRefs`
- `leanRefs` should not automatically synthesize tracking entries
- disagreement between them is not, by itself, a violation of ownership boundaries

They answer different questions.

### Example difference

A node may have a `leanRefs` entry pointing to a declaration that no longer contains `informal[...]`, because the declaration has already been fully formalized.
That is not the same thing as the node being currently tracked by the informal layer.

## Workflow-state boundary

The old main-worktree `Informalize` metadata model mixed a fair amount of workflow state into the informal sidecar store.
The rewrite should not reproduce that pattern.

## V1 rule

The informal layer should not maintain its own copies of node-attached workflow state such as:

- statuses
- parent links
- issue lists
- source refs
- knowledge refs
- tags

If the project needs node-level workflow state, it should come from the knowledge base.
If the project later needs orchestration-level state above the node model, that should live in a higher layer.

## If current knowledge-base metadata is not enough

If future work shows that additional node-level workflow fields are truly needed, the first options should be:

1. deliberately extend the knowledge-base metadata model, or
2. store higher-level orchestration state in a later layer

The fallback should **not** be “add a second informal-layer metadata store.”

## Canonical vs derived summary table

A useful summary is:

### Canonical in Lean source

- where `informal[...]` appears
- which declarations contain those terms
- the surrounding formal code

### Canonical in knowledge base

- node id
- body
- node metadata
- node relationships
- node-level authored Lean refs and descriptive/workflow metadata

### Persistent but bridge-specific in the informal layer

- declaration->set-of-references linkage in the environment extension

### Derived in the informal layer

- reverse reference->declaration views
- declaration dependency views
- projected reference dependency views
- presentation summaries/payloads
- process-local caches

## Recommended module placement

The v1 implementation may not need a dedicated `AFTK/Informal/BridgeState.lean` file immediately, because much of this design is an ownership policy spanning several modules.

However, if the code later accumulates enough shared bridge-local context or cache/path helpers, a dedicated module such as:

```text
AFTK/Informal/BridgeState.lean
```

would be an appropriate home for:

- small bridge-context bundles
- noncanonical bridge-cache types
- helpers for any future persisted informal-derived-state paths under `knowledgebase/.aftk/`

This should remain optional until real implementation pressure appears.

## Testing implications

The bridge-state design should lead to tests that check at least the following:

- tracking state contains declaration↔reference linkage but not copied node bodies or metadata
- reverse indexes and dependency views can be rebuilt from tracking state plus environment data
- presentation payloads are derived from current resolved nodes rather than cached canonical copies
- changes to knowledge-base node content affect derived presentation after re-resolution
- no code path reintroduces an `informal/` sidecar content dependency
- CLI/query behavior remains correct without any extra persisted bridge-local filesystem state

The detailed test strategy belongs in `plans/informal/testing.md`, but these are the state-boundary invariants worth protecting.

## Rejected alternatives

The following designs should be rejected for v1:

### 1. Reintroduce a separate `informal/...` markdown/json store

Rejected because it violates the single-source-of-truth architecture.

### 2. Persist resolved node snapshots in the tracking layer

Rejected because it duplicates knowledge-base content and risks staleness.

### 3. Give the informal layer its own node metadata/workflow schema

Rejected because node-attached metadata belongs to the knowledge base.

### 4. Persist dependency indexes as canonical bridge state

Rejected because dependency views are derived from environment + tracking state.

### 5. Conflate tracking with knowledge-base `leanRefs`

Rejected because they have different meanings and ownership boundaries.

### 6. Make correctness depend on process-local caches

Rejected because caches should be disposable accelerators only.

## Lean 4 and current-project reuse findings

The rewrite already has most of the right ingredients for this state boundary:

- the knowledge-base layer already owns canonical node content and metadata
- the tracking design already keeps persistent bridge state down to declaration↔reference linkage
- the dependency design already treats indexes as derived
- the presentation design already treats summaries/payloads as derived views
- the current project already uses Lean environment extensions for compiled derived state without introducing extra authored filesystem stores

Core Lean makes one state-boundary point especially explicit: persistent environment extension data is serialized from the main environment’s `.sync` view at the end of the file.
So declaration↔reference linkage already has a natural compiled persistence mechanism in `.olean` data, which further reduces any need for a second informal-layer filesystem state area.

So this bridge-state design is mainly about preserving those boundaries consistently as implementation proceeds.

## Open questions for later refinement

- Will the informal layer eventually need a small shared bridge-context type wrapping knowledge-base root/config plus reusable resolver helpers?
- If persisted informal-derived caches are ever added, what exact subdirectory layout under `knowledgebase/.aftk/` should they use?
- Should future tooling expose diagnostics that compare knowledge-base `leanRefs` with actual tracked `informal[...]` usage, while still keeping them semantically distinct?

These are refinements, not blockers for the first implementation.

## Summary

The rewrite’s informal layer should own very little persistent state of its own.
Its canonical authored ingredients are split between:

- Lean source, which owns where `informal[...]` appears, and
- the knowledge base, which owns node identity, content, metadata, and node-level relationships.

The informal layer’s own persistent bridge state should be limited to declaration-level declaration↔reference linkage. Dependency indexes, reverse lookups, presentation payloads, and caches should remain derived. The rewrite should not reintroduce a separate `informal/...` store, a second metadata schema, or canonical persisted bridge-local graph data.
