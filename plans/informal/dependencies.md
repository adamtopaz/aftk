# Informal Dependency Design

## Status

Component plan and implementation-status document for informal-layer dependency analysis.
This document refines the overall informal-layer plan in `plans/informal.md` and works together with `plans/informal/tracking.md`, `plans/informal/elaboration.md`, `plans/informal/references.md`, `plans/informal/cli.md`, `plans/informal/layout.md`, and `plans/informal/testing.md`.

## Component implementation status

- Overall status: Implemented (initial v1)
- Implemented in code: Yes
- Last updated basis: repository now derives declaration and reference dependency views in `AFTK.Informal.Dependencies` from Lean environment usage plus tracked declaration↔reference linkage.

## Purpose

This document defines the dependency views the informal layer should compute from:

- Lean declaration dependency information, and
- declaration-level informal-reference tracking data.

It explains:

- what a declaration-level informal dependency means
- how to project declaration dependencies onto referenced knowledge-base nodes
- what convenience leaf-like views the layer may expose
- what belongs in the informal layer versus higher scaffold-orchestration layers
- what data should be derived on demand rather than persisted canonically

The key design clarification already settled in `plans/informal.md` is:

> The informal layer should own declaration-level dependency analysis and direct projections from declaration dependencies to referenced-node dependencies, while frontier computation, readiness classification, prioritization, and broader scaffold orchestration should remain higher-layer responsibilities.

This document makes that boundary precise.

## Design goals

The dependency layer should:

- compute useful dependency views directly from Lean and informal-layer state
- preserve the earlier ability to inspect tracked declaration dependencies
- project those dependencies onto tracked knowledge-base references
- remain deterministic and automation-friendly
- avoid pretending that informal dependency views are a full scaffold engine
- avoid duplicating knowledge-base content or introducing a second graph store
- stay compatible with declaration-level tracking rather than requiring per-site state

## Scope and non-scope

### In scope

- declaration-level dependency semantics among tracked declarations
- projection from declaration dependencies to referenced-node dependencies
- deterministic output shapes for declaration and reference dependency rows
- convenience leaf-like views derived from empty dependency sets
- cycle-safe traversal rules
- boundaries between dependency analysis and higher-layer orchestration

### Out of scope

- term elaboration itself
- knowledge-base reference parsing and resolution
- knowledge-base search or semantic retrieval
- workflow readiness classification
- unresolved-node frontier selection as a full orchestration decision
- prioritization policies
- source-gap analysis

Those belong to other component plans or higher layers.

## Reference point from the earlier implementation

The earlier `Informalize` CLI computes two important views:

- tracked declaration dependencies
- projected location dependencies

Its core behavior is:

1. collect tracked declarations from the persistent environment extension
2. use Lean constant-usage information to traverse declaration dependencies
3. restrict reported declaration dependencies to tracked declarations
4. project those declaration dependencies onto tracked informal locations
5. report empty-dependency rows as leaves in the selected view

That is a good model for AFTK.
The key changes are:

- tracked items are now `InformalReference` values backed by knowledge-base node ids rather than `LocationId`s
- declaration tracking no longer has to support empty reference sets created by bare `informal`
- the projection target is a knowledge-base-backed node-reference set rather than an `informal/...` sidecar id set

## Core design decision

The informal layer should define two primary dependency views.

### 1. Declaration dependency view

This answers:

> Which tracked declarations does this tracked declaration depend on?

### 2. Reference dependency view

This answers:

> Which referenced knowledge-base nodes appear in declarations that the source declaration(s) depend on?

The second view is a projection of the first, not an independent semantic graph learned from the knowledge base.
That distinction is important.

## Declaration dependency semantics

The declaration dependency view should be based on Lean’s existing declaration-usage graph.

### Recommended meaning

A tracked declaration `A` depends on a tracked declaration `B` iff:

- there is a path in Lean constant usage from `A` to `B`, and
- `B` is itself one of the tracked declarations of the informal layer, and
- `B ≠ A`

This intentionally allows traversal through intermediate declarations that are not themselves tracked.
That matches the earlier behavior and is very useful in practice.

### Why use transitive reachability rather than only one-step tracked edges

Suppose a tracked declaration depends on several helper declarations that are not themselves tracked, and those helpers eventually depend on another tracked declaration.
The informal layer still wants to know about that tracked prerequisite.

So the recommended v1 declaration dependency semantics are:

- traverse the full Lean constant-usage graph transitively
- report only tracked declarations in the final dependency set

This gives a useful prerequisite view without requiring every intermediate helper to be tracked explicitly.

## Source of declaration dependency information

The dependency layer should reuse Lean environment information rather than maintaining its own manually authored dependency graph.

### Recommended Lean reuse point

The earlier implementation uses `ConstantInfo.getUsedConstantsAsSet`.
That remains the right kind of source for v1.

A relevant Lean-core detail is that `ConstantInfo.getUsedConstantsAsSet` is not body-only:

- it unions constants from the declaration type and value, and
- it has special handling for inductives, constructors, recursors, and opaque declarations.

So the resulting dependency view is best understood as a dependency view over compiled declaration usage as Lean sees it, not merely over the surface term body.

At a high level, dependency analysis should:

- look up a declaration in the environment
- obtain its used constants
- traverse recursively from those used constants
- collect tracked declarations reached during traversal

### If a declaration is missing from the environment

A missing environment entry should simply behave like having no used constants for dependency-computation purposes.
That keeps the algorithm total and simple.

## Proposed declaration-level types

A good v1 shape is:

```lean
namespace AFTK.Informal

structure InformalDeclDependencyEntry where
  declName : Lean.Name
  dependencies : Array Lean.Name
  deriving Repr, Inhabited

end AFTK.Informal
```

### Semantics

- `declName` is a tracked declaration
- `dependencies` is the deterministic array of tracked declarations it transitively depends on
- self-dependencies are excluded

## Declaration traversal algorithm

A good v1 algorithm follows the earlier design closely.

### Inputs

- the current Lean environment
- the set of tracked declarations from the tracking layer
- one tracked root declaration

### Traversal rule

Starting from the root declaration’s used constants:

- traverse recursively through used constants
- maintain a visited set to avoid loops and repeated work
- when a reached declaration is tracked, add it to the root’s dependency set
- continue traversal through both tracked and untracked declarations so long as they have used-constant information available
- never add the root declaration itself as its own dependency

### Output

The result for one root is a set of tracked declarations.
The whole declaration dependency index is obtained by running this traversal for each tracked declaration.

## Cycle handling

The traversal should be cycle-safe even if future environments or generated declarations expose cyclic-looking constant-usage structures.

### Rules

- maintain a visited set per root traversal
- remove self-dependencies from the final result
- allow cycles among non-root declarations to collapse naturally via the visited set

### Consequence

A cycle among tracked declarations should simply appear as mutual dependencies in the output, without nontermination.

## Reference dependency semantics

The reference dependency view should be a projection from declaration dependencies and declaration-level tracking data.
It should not be inferred directly from knowledge-base content.

### Recommended meaning

A reference `R` depends on a reference `S` iff:

- some tracked declaration referencing `R` depends on some tracked declaration referencing `S`
- and `S ≠ R`

This means reference dependencies are induced by declaration dependencies, not by node metadata or knowledge-base relationships.

## Projection algorithm

The recommended v1 projection is:

1. compute the declaration dependency index
2. compute the declaration->reference index from the tracking layer
3. compute the reference->declaration reverse index from the tracking layer
4. for each source reference `R`:
   - find all tracked declarations that reference `R`
   - union the tracked declaration dependencies of those declarations
   - for each dependent declaration, union the references attached to that dependent declaration
   - remove `R` from the final set if present

This is the direct analogue of the earlier location-dependency projection.

## Proposed reference-level types

A good v1 shape is:

```lean
namespace AFTK.Informal

structure InformalReferenceDependencyEntry where
  ref : InformalReference
  dependencies : Array InformalReference
  deriving Repr, Inhabited

end AFTK.Informal
```

### Semantics

- `ref` is one tracked informal reference
- `dependencies` is the deterministic array of references induced by dependent declarations
- self-dependencies are excluded

## Important overapproximation property

Because tracking is declaration-level, the reference dependency view is also declaration-level and therefore intentionally approximate.

### Example

If one declaration references both:

- `group.basic.definition`
- `group.basic.operation_note`

and that declaration depends on another declaration referencing:

- `algebra.monoid.definition`

then both source references may be reported as depending on `algebra.monoid.definition`.

That is acceptable in v1.
The informal layer is not trying to recover per-site or per-subexpression dependence.
It is providing a useful declaration-level projected view.

## Leaf-like views

The dependency layer may expose convenience “leaves” derived from empty dependency sets.

### Declaration dependency leaves

A declaration dependency leaf is a tracked declaration whose dependency set is empty in the declaration dependency view.

### Reference dependency leaves

A reference dependency leaf is a tracked reference whose dependency set is empty in the projected reference dependency view.

## Boundary with higher-layer frontier computation

These leaf-like views are useful, but they are **not** the same thing as full workflow frontier computation.

### The informal layer may do

- identify empty-dependency rows in a selected dependency view
- report them as dependency leaves for inspection convenience

### The informal layer should not do

- decide whether a node is unresolved or already formalized
- combine dependency leaves with workflow status/metadata to define the full active frontier
- rank or prioritize leaves for work scheduling
- classify leaves as ready, blocked, or needing sources

Those responsibilities belong to higher layers.

## Relationship to knowledge-base relationships

The reference dependency view should not be confused with knowledge-base relationship metadata such as prerequisite links, examples, related items, or refinement links.

### Important distinction

- informal dependency view: induced by Lean declaration usage plus tracked references
- knowledge-base relationship graph: authored metadata in the knowledge base itself

Both may be useful, but they are different graphs with different meanings.
The informal layer should not collapse them together in v1.

## What should be canonical versus derived

The dependency layer should treat dependency indexes as derived data.

### Canonical ingredients

The canonical ingredients for dependency analysis are:

- the Lean environment
- the informal tracking state

### Derived outputs

The following should be computed on demand in v1:

- declaration dependency index
- reference dependency index
- leaf arrays derived from those indexes

This follows the same philosophy as the tracking layer: keep persisted canonical bridge state small, and derive richer views when queried.

## Public query APIs

A reasonable v1 library surface is:

```lean
def allInformalDeclDependencyEntries : CoreM (Array InformalDeclDependencyEntry)
def informalDeclDependencyEntry? (declName : Lean.Name) : CoreM (Option InformalDeclDependencyEntry)

def allInformalReferenceDependencyEntries : CoreM (Array InformalReferenceDependencyEntry)
def informalReferenceDependencyEntry? (ref : InformalReference) : CoreM (Option InformalReferenceDependencyEntry)

def informalDeclDependencyLeaves : CoreM (Array Lean.Name)
def informalReferenceDependencyLeaves : CoreM (Array InformalReference)
```

### Behavior

- all arrays are sorted deterministically
- targeted lookup returns `none` when the target is absent
- dependency entries are derived from current environment + tracking state, not persisted separately

## Deterministic ordering policy

Outputs should be deterministic.

### Required ordering

- declaration dependency rows sorted by `Lean.Name`
- each declaration dependency array sorted by `Lean.Name`
- reference dependency rows sorted by underlying `NodeId`
- each reference dependency array sorted by underlying `NodeId`
- leaf arrays sorted in the corresponding order

This matters for:

- stable CLI output
- test reproducibility
- higher-layer automation

## Relationship to the tracking layer

The tracking layer supplies the declaration↔reference incidence data that dependency analysis needs.
The dependency layer should not rebuild that information from scratch.

### Dependency layer should reuse

- declaration-centric tracked entries
- derived reverse reference lookup from the tracking layer or equivalent helper logic

### Dependency layer should not do

- rescan source syntax for `informal[...]`
- inspect knowledge-base files to guess which declarations reference which nodes

That would violate the layering.

## Relationship to the placeholder mechanism

Dependency analysis should be driven by declaration usage and tracking data, not by searching arbitrary terms for placeholder-axiom occurrences.

### Reason

The placeholder primitive alone does not tell us which knowledge-base node was referenced.
The tracked reference linkage comes from elaboration-time tracking.

So dependency analysis should be built on:

- Lean declaration usage for declaration edges
- tracking state for declaration↔reference edges

not on placeholder-term scanning.

## Error behavior

Dependency queries are mostly derived views and should be low-drama operationally.

### Expected behavior

- if there are no tracked declarations, return empty dependency results
- if a particular target declaration or reference is not tracked, targeted lookup returns `none`
- if an environment lookup fails for some declaration during traversal, treat it as contributing no further used constants rather than throwing

### What should not happen

Dependency-query APIs should not fail merely because:

- some declaration has no tracked references
- a reverse projected row ends up empty
- there are no dependency leaves

## Recommended internal helpers

Implementation will likely want helpers such as:

- `trackedDeclNameSet`
- `usedConstants`
- `collectReachableTracked`
- `transitiveDeclDependencyIndex`
- `declReferenceIndex`
- `referenceDeclIndex`
- `referenceDependencyIndex`
- `sortedDeclDependencyRows`
- `sortedReferenceDependencyRows`

These do not need to be public APIs by default.

## Testing implications

The dependency design should lead to tests that check at least the following:

- tracked declaration dependency traversal reaches tracked declarations through untracked intermediates
- self-dependencies are removed
- duplicate reachable declarations are deduplicated
- projected reference dependencies are computed from declaration dependencies correctly
- repeated declarations referencing the same reference union properly in the projection
- leaf arrays match the rows with empty dependency sets
- outputs are deterministic
- dependency queries over empty tracking state return empty results

The full test strategy belongs in `plans/informal/testing.md`, but these are the core dependency invariants.

## Rejected alternatives

The following alternatives should be rejected for v1:

### 1. Treat knowledge-base relationship metadata as the same graph as informal dependency analysis

Rejected because they have different meanings and sources of truth.

### 2. Persist dependency indexes as canonical bridge state

Rejected because dependency views are naturally derived from environment + tracking state and should not become a second canonical graph store in v1.

### 3. Require per-site tracking in order to compute dependencies

Rejected because the public tracking model is intentionally declaration-level.

### 4. Let the informal layer implement full workflow frontier logic

Rejected because frontier computation in the workflow sense depends on more than dependency emptiness.

### 5. Restrict declaration dependencies to only one-step tracked uses

Rejected because that would hide meaningful tracked prerequisites behind untracked helper declarations and would lose the most useful part of the earlier behavior.

## Lean 4 and current-implementation reuse findings

The earlier dependency code already shows the right overall approach for v1.
The main reusable ideas are:

- use `ConstantInfo.getUsedConstantsAsSet` or equivalent environment support for declaration usage
- traverse recursively with a visited set
- collect only tracked declarations into the reported dependency set
- project declaration dependencies to tracked references by combining declaration->reference and reference->declaration indexes
- sort only at the public-output boundary

Core Lean adds one important semantic detail: `ConstantInfo.getUsedConstantsAsSet` already bakes in Lean’s view of dependencies across declaration types, values, and certain declaration-kind-specific auxiliary names.
That makes it a good compiled-environment source for v1, but it also means the informal dependency view should be documented as Lean-usage-based rather than narrowly body-text-based.

AFTK should preserve this architecture while replacing `LocationId`-based projection with `InformalReference` values backed by knowledge-base node ids.

## Open questions for companion docs

This document intentionally leaves nearby details to companion plans:

- The tracking-layer declaration/reference incidence structures belong in `plans/informal/tracking.md`.
- The exact reference type belongs in `plans/informal/references.md`.
- CLI command families and rendering belong in `plans/informal/cli.md`.
- Module boundaries and helper placement belong in `plans/informal/layout.md`.
- Test fixtures and regression coverage belong in `plans/informal/testing.md`.

## Summary

The informal layer should compute two derived dependency views:

- a declaration dependency view over tracked declarations, based on transitive Lean constant-usage reachability restricted to tracked declarations, and
- a reference dependency view obtained by projecting those declaration dependencies through declaration-level `InformalReference` tracking data.

These views may expose convenience leaves as empty-dependency rows, but they should not be confused with full workflow frontier computation. The dependency layer should remain a deterministic, declaration-level bridge analysis layer built from Lean environment information plus informal tracking state, not a second canonical graph store and not a higher-level orchestration engine.
