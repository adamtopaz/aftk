# Informal Tracking Design

## Status

Component plan and implementation-status document for informal-layer tracking.
This document refines the overall informal-layer plan in `plans/informal.md` and works together with `plans/informal/elaboration.md`, `plans/informal/references.md`, `plans/informal/placeholder.md`, `plans/informal/dependencies.md`, `plans/informal/layout.md`, and `plans/informal/testing.md`.

## Component implementation status

- Overall status: Not implemented
- Implemented in code: No
- Last updated basis: rewrite worktree has no informal-layer tracking module yet; this design is based on `plans/informal.md`, `plans/informal/elaboration.md`, `plans/informal/references.md`, and the current main-worktree persistent-environment-extension design in `/home/dev/aftk/Informalize/Extension.lean`

## Purpose

This document defines how the informal layer should track successful uses of `informal[...]` across Lean declarations.
It explains:

- what should count as a tracked occurrence
- what data should be persisted in the environment extension
- how repeated uses should be deduplicated
- how imported modules should merge tracking state
- what public query APIs the layer should expose
- what derived indexes should be computed on demand versus persisted

The key design clarification already settled in `plans/informal.md` is:

> The public tracking surface should remain declaration-level rather than per-site.

That decision shapes the whole design.

## Design goals

The tracking layer should:

- record which declarations successfully use `informal[...]`
- record which knowledge-base nodes those declarations reference
- remain derived from successful elaboration rather than from ad hoc file scanning
- merge cleanly across imported modules
- deduplicate repeated references within a declaration
- expose stable query APIs for declaration→reference and reference→declaration questions
- avoid persisting duplicated knowledge-base content or metadata
- provide deterministic results to CLI and higher-layer consumers
- stay simple enough that it does not become a second knowledge store

## Scope and non-scope

### In scope

- persistent environment extension design for informal-reference tracking
- tracked occurrence entry shape
- aggregated state shape
- deduplication rules
- imported-state merge behavior
- declaration-level query APIs
- reverse lookup from reference to declarations as a derived view
- boundaries between canonical tracked state and derived indexes

### Out of scope

- the actual term elaboration pipeline that calls the tracking hook
- the placeholder kernel primitive itself
- detailed dependency-graph semantics above declaration/reference edges
- hover/info rendering
- CLI argument parsing and rendering
- knowledge-base content storage and metadata schemas

Those belong to companion plans.

## Reference point from the main-worktree implementation

The current main-worktree `Informalize` implementation uses a `SimplePersistentEnvExtension` with:

- one input entry per successful elaborated occurrence
- a state mapping `declName -> NameSet` of referenced locations
- union-based merging of imported states
- declaration-level public queries such as:
  - `allInformalDeclEntries`
  - `informalDeclEntry?`

That shape is still a good model for the rewrite.
The main change is not the tracking pattern but the tracked payload:

- old payload: optional `LocationId`/`Name`
- new payload: resolved informal reference identity backed by `KnowledgeBase.NodeId`

Because bare `informal` support is being removed, the rewrite can simplify the main-worktree design further:

- there is no longer any need to track declarations with an empty reference set
- every tracked declaration should have at least one referenced node id

## Core design decision

The rewrite should keep the same overall strategy:

- feed one entry per successful elaborated `informal[...]` site into a persistent environment extension
- aggregate those site entries into declaration-level reference sets
- expose declaration-level and reverse reference-level views as the public query surface

This gives simple elaborator integration while still honoring the declaration-level tracking policy.

## What counts as a tracked occurrence

A tracked occurrence should be created only when all of the following are true:

- the user wrote `informal[...]`
- the occurrence elaborated successfully
- the bracketed reference validated as a knowledge-base node id
- the reference resolved successfully through the knowledge base
- the elaborator had a real enclosing declaration context

### What should not be tracked

The tracking layer should not record:

- syntactically malformed bracket payloads
- unresolved or missing references
- occurrences rejected for invalid command/pseudo-declaration contexts
- failed elaboration attempts that never produced a valid placeholder term

This preserves the rule that tracking reflects successful bridge construction, not failed attempts.

## Declaration-level tracking policy

The public tracking surface should remain declaration-level.
That means a declaration should be modeled as referencing a **set** of informal references.

### Consequences

If a declaration contains the same reference multiple times, the public tracked state should still record it only once.

For example:

```lean
def foo : Nat :=
  informal[group.basic.definition] + informal[group.basic.definition]
```

should be tracked as:

- declaration `foo`
- references `{group.basic.definition}`

not as two separate public occurrences.

### What is intentionally lost

The declaration-level policy intentionally loses:

- exact source-site multiplicity
- site ordering within a declaration
- direct public access to per-site tags

This is acceptable because:

- the design decision has already settled against a per-site public API
- hover/info support can still use local info-tree data at the term site
- later tooling interested in declaration/reference structure does not need site multiplicity for v1

## Proposed Lean-level types

A good v1 design is:

```lean
namespace AFTK.Informal

structure InformalOccurrence where
  declName : Lean.Name
  ref : InformalReference
  deriving Repr, Inhabited, BEq, Hashable

abbrev InformalTrackingState := Std.HashMap Lean.Name (Std.HashSet InformalReference)

structure InformalDeclEntry where
  declName : Lean.Name
  refs : Array InformalReference
  deriving Repr, Inhabited

structure InformalReferenceEntry where
  ref : InformalReference
  declNames : Array Lean.Name
  deriving Repr, Inhabited

end AFTK.Informal
```

### Why this split is useful

- `InformalOccurrence` is the per-site input entry type used by the elaborator and persistent extension
- `InformalTrackingState` is the aggregated internal state keyed by declaration
- `InformalDeclEntry` is the main public declaration-centric query row
- `InformalReferenceEntry` is the main public reverse-lookup query row

This cleanly separates input events, internal state, and public query shapes.

## Why store `InformalReference`, not `ResolvedInformalReference`

The persistent tracking state should store semantic references, not fully resolved nodes.

### Reasons

- storing resolved nodes would duplicate knowledge-base content in compiled environment state
- resolved nodes depend on a particular storage root and current canonical files
- the environment extension should record stable declaration↔reference linkage, not cached content snapshots
- live resolution/rendering can happen later when higher layers actually need knowledge-base content

So the persistent state should store only the validated reference identity.

## Why not store tags in persistent state

The placeholder `tag` is important for term distinctness, but it should not be part of the public tracking state.

### Reasons

- the public tracking policy is declaration-level, not per-site
- tags are implementation-level occurrence identifiers, not declaration/reference relationships
- storing tags would invite a public per-site API that the design has explicitly rejected
- info-tree and elaboration-local mechanisms already cover site-specific tooling needs

If a future use case truly needs persisted per-site tags, that should be a separate deliberate design change, not an accidental consequence of the v1 tracking model.

## Persistent environment extension design

The rewrite should use a `SimplePersistentEnvExtension` in the same general style as the main-worktree implementation.

### Recommended shape

```lean
initialize informalExt : SimplePersistentEnvExtension InformalOccurrence InformalTrackingState := ...
```

### Why `SimplePersistentEnvExtension`

This is the right default because the tracking data is:

- append-like at elaboration time
- naturally mergeable across imported modules
- read frequently by later queries
- modest in size relative to whole-project environments

The current main-worktree implementation already shows that this pattern fits the problem well.

### Recommended async mode

The safest initial choice is synchronous extension updates, mirroring the current design.
That keeps behavior simple and deterministic.

However, Lean core’s `EnvExtension.AsyncMode` documentation is relevant here: `.async .mainEnv` is specifically intended for map-like extensions keyed by the surrounding top-level declaration name.
Because informal tracking is exactly declaration-keyed, that mode may become the better long-term fit if elaboration-time writes need to avoid `.sync` blocking under async elaboration.

So the v1 recommendation is:

- start with `.sync` if that keeps the first implementation simpler
- keep the design compatible with a later move to declaration-keyed async access if profiling or async-elaboration behavior makes that worthwhile

## Aggregation semantics

Each successful elaborated site should add one `InformalOccurrence` entry.
The extension state should aggregate those entries by declaration.

### Aggregation rule

For each input entry `(declName, ref)`:

- look up the current set of refs for `declName`
- insert `ref` into that set
- store the updated set back into the state

### Deduplication rule

If the same declaration references the same node multiple times, the state should still contain that reference only once.

### No empty entries

Because bare `informal` is removed, the state should never intentionally store a declaration with an empty ref set.
A declaration is either tracked with at least one reference or not tracked at all.

## Imported-state merge semantics

Imported modules should merge by set union.

### Rule

When imported extension payloads are combined:

- declarations with distinct names should both appear
- if the same declaration name is present from imported arrays, their reference sets should be unioned
- repeated identical `(declName, ref)` entries should collapse harmlessly

### Determinism

The merge operation should be semantically deterministic even if the internal map/set structures are hash-based.
Public query functions should sort their outputs explicitly rather than relying on map iteration order.

## Public query APIs

The informal layer should expose a small reusable library API over the extension state.

### Declaration-centric queries

Recommended APIs:

```lean
def allInformalDeclEntries : CoreM (Array InformalDeclEntry)
def informalDeclEntry? (declName : Lean.Name) : CoreM (Option InformalDeclEntry)
```

Behavior:

- results are sorted deterministically by declaration name
- each `refs` array is sorted deterministically by reference/node id
- only declarations with at least one tracked ref are returned

### Reference-centric queries

Because higher layers and the CLI need to answer “which declarations reference this node?”, the library should also expose a reverse view.

Recommended APIs:

```lean
def allInformalReferenceEntries : CoreM (Array InformalReferenceEntry)
def informalReferenceEntry? (ref : InformalReference) : CoreM (Option InformalReferenceEntry)
```

Behavior:

- reverse lookup may be derived on demand from the declaration-centric state in v1
- results are sorted deterministically by reference/node id
- each `declNames` array is sorted deterministically by declaration name

### Why derive reverse lookup on demand in v1

The declaration-centric mapping is the more fundamental canonical tracked state.
A reverse mapping can be rebuilt cheaply from it when needed.
This keeps the extension state simple and avoids maintaining redundant persistent indexes too early.

## Deterministic output policy

Although the internal state may use hash-based structures, public results should be deterministic.

### Required sorting points

- declaration rows sorted by `Lean.Name`
- references within one declaration sorted by underlying `NodeId`
- reference rows sorted by underlying `NodeId`
- declarations within one reference row sorted by `Lean.Name`

This is important for:

- CLI stability
- test stability
- predictable higher-layer behavior

## Relationship to the knowledge base

The tracking layer should record **which nodes are referenced**, not duplicate knowledge-base content.

### The tracking state should not store

- markdown bodies
- knowledge-base metadata fields
- canonical node paths
- resolved node snapshots
- search indexes

### The tracking state may store

- declaration names
- validated informal references wrapping node ids
- derived reverse indexes computed from those references

If a consumer needs node content or metadata, it should resolve the tracked reference through the knowledge-base layer at read time.

## Relationship to the placeholder mechanism

Tracking and placeholders are related but not identical.

### Important distinction

- placeholder use inside terms is what makes elaboration succeed
- tracking records that a declaration successfully used a knowledge-base-backed informal placeholder

Tracking should therefore be driven by the elaborator hook, not by scanning arbitrary expressions for the placeholder axiom later.

### Consequence

If someone were to use the placeholder primitive directly without going through `informal[...]`, that should not automatically count as an informal-layer tracked reference.
The tracking layer is specifically about successful `informal[...]` bridge occurrences.

## Relationship to dependency analysis

Tracking provides the raw declaration↔reference linkage needed by later dependency queries.
It should not itself encode the whole dependency-analysis policy.

### Tracking layer responsibility

- know which declarations reference which node ids
- provide deterministic declaration-centric and reference-centric views

### Dependency layer responsibility

- combine tracked declaration/reference data with declaration dependency information
- project declaration dependencies to referenced-node dependencies
- compute leaf-like derived views when appropriate

That separation keeps the tracking layer small and focused.

## Error behavior

Tracking functions themselves should be simple.
Most errorful conditions happen before tracking, during elaboration and reference resolution.

### Expected behavior

- successful elaboration records an occurrence
- failed elaboration records nothing
- querying tracking state from an environment with no tracked references returns empty results rather than an error

### Not-found query behavior

For targeted queries such as `informalDeclEntry?` or `informalReferenceEntry?`, absence should be represented as `none`, not as an exception.

## Recommended helper functions

In addition to the public queries above, implementation will likely want internal helpers such as:

- `addOccurrenceToState`
- `mergeImportedState`
- `referenceSetToSortedArray`
- `reverseIndexFromState`

These helpers should remain internal implementation details unless a clear reuse need emerges.

## Testing implications

The tracking design should lead to tests that check at least the following:

- one successful `informal[...]` creates one tracked declaration entry
- repeated identical references in one declaration are deduplicated
- multiple distinct references in one declaration are all preserved
- declarations are not tracked when elaboration fails
- imported-module tracking data merges by union
- reverse lookup from reference to declarations is correct
- public query outputs are deterministic
- no empty tracked declaration entries are created

The full test strategy belongs in `plans/informal/testing.md`, but these are the core invariants to preserve.

## Rejected alternatives

The following alternatives should be rejected for v1:

### 1. Public per-site tracking API

Rejected because the layer has already chosen a declaration-level public surface.
Per-site state would add complexity and encourage overfitting tooling to source-position details.

### 2. Persist full resolved nodes in the environment extension

Rejected because it duplicates knowledge-base content and couples compiled environments too tightly to filesystem state.

### 3. Maintain both declaration->refs and ref->declarations as persistent canonical state

Rejected for v1 because the reverse mapping is easily derived and redundancy would complicate maintenance without enough benefit initially.

### 4. Track generic placeholder primitive use instead of successful `informal[...]` elaboration

Rejected because the bridge layer is specifically about knowledge-base-backed informal references, not arbitrary uses of the placeholder axiom.

### 5. Track multiplicity counts of repeated references inside a declaration

Rejected because declaration-level set semantics are the intended public model.

## Lean 4 and current-implementation reuse findings

The current main-worktree extension is already a strong template for the rewrite.
The main reusable ideas are:

- `SimplePersistentEnvExtension` as the persistence mechanism
- one input entry per successful elaborated site
- aggregation into a declaration-keyed map
- set-based deduplication within each declaration
- imported-state union logic
- deterministic sorting at public query boundaries rather than in the internal state

Core Lean fills in a few useful details behind that template:

- `SimplePersistentEnvExtension` is really a `PersistentEnvExtension α α (List α × σ)`, so exported entry arrays and aggregated state are intentionally separate concerns
- `addImportedFn` receives imported entries grouped as `Array (Array α)`, which matches the union-style merge logic this design already wants
- `toArrayFn` controls exported per-module entry materialization, but deterministic public query sorting can still remain a separate concern at read time
- Lean’s async-mode documentation identifies `.async .mainEnv` as a particularly good fit for declaration-keyed map-like extensions, giving the rewrite a plausible future refinement path beyond `.sync`
- `SimplePersistentEnvExtension.replayOfFilter` exists as a useful helper if a later async/replay-aware version of the extension needs to be introduced

The rewrite should keep the overall architecture while replacing `LocationId`/`Name` payloads with `InformalReference` values backed by `KnowledgeBase.NodeId`.

## Open questions for companion docs

This document intentionally leaves nearby details to companion plans:

- The exact elaborator hook timing belongs in `plans/informal/elaboration.md`.
- The exact reference wrapper and resolution functions belong in `plans/informal/references.md`.
- The dependency graph and node-projection semantics belong in `plans/informal/dependencies.md`.
- CLI rendering and command families belong in `plans/informal/cli.md`.
- Module boundaries and exported APIs belong in `plans/informal/layout.md`.
- Test fixtures and integration coverage belong in `plans/informal/testing.md`.

## Summary

The rewrite’s tracking layer should use a `SimplePersistentEnvExtension` that receives one entry per successful `informal[...]` elaboration site and aggregates those entries into declaration-level sets of `InformalReference` values.

The canonical public tracking surface should stay declaration-level, with reverse reference->declaration views derived on demand. The tracking state should record only stable declaration↔reference linkage, not per-site tags, not multiplicity counts, and not duplicated knowledge-base content.

That preserves the best part of the current main-worktree tracking architecture while aligning it with the rewrite’s knowledge-base-backed reference model and declaration-level public API.
