# Informal Lean library

Import the public root with:

```lean
import AFTK.Informal
```

This re-exports the current informal modules:

- `Syntax`
- `Placeholder`
- `References`
- `Tracking`
- `Dependencies`
- `Presentation`
- `Options`
- `Elaborator`

## Module guide

### `AFTK.Informal.Syntax`

Defines the bracketed term syntax:

```lean
informal[group.basic.definition]
```

Important details:

- the syntax category is `informalNodeId`
- the current grammar accepts identifier-shaped payload syntax
- the elaborator later validates the payload semantically as a knowledge-base `NodeId`
- helper: `informalNodeIdString?`

### `AFTK.Informal.Placeholder`

Defines the primitive used during elaboration:

```lean
axiom Informal.{u} (tag : Lean.Name) (α : Sort u) : α
```

This module is intentionally tiny so other informal modules can depend on it without bringing in heavier logic.

### `AFTK.Informal.Options`

Registers the Lean option:

```text
aftk.informal.root
```

This option overrides the knowledge-base root used during informal elaboration and worker-side rich hover resolution.

### `AFTK.Informal.References`

Defines the core reference types and knowledge-base-backed resolution helpers.

Key types:

- `InformalReference`
- `ResolvedInformalReference`

Key functions:

- `InformalReference.ofNodeId`
- `InformalReference.ofString?`
- `InformalReference.render`
- `InformalReference.startsWithSegmentPrefix`
- `informalReferenceOfString?`
- `resolveInformalReferenceIn`
- `resolveInformalReferenceAtRoot`
- `resolveInformalReference`

Important boundary:

- `InformalReference` stores only a `NodeId`
- `ResolvedInformalReference` carries the loaded `StoredNode`
- reference resolution is delegated to `AFTK.KnowledgeBase.Storage`

### `AFTK.Informal.Tracking`

Defines persistent declaration/reference tracking.

Key types:

- `InformalOccurrence`
- `InformalDeclEntry`
- `InformalReferenceEntry`

Key functions:

- `addInformalOccurrence`
- `allInformalDeclEntries`
- `informalDeclEntry?`
- `allInformalReferenceEntries`
- `informalReferenceEntry?`

Important semantics:

- public tracking is declaration-level
- repeated references inside one declaration are deduplicated
- imported modules contribute tracking data when environments are loaded with `loadExts := true`
- outputs are sorted deterministically

### `AFTK.Informal.Dependencies`

Builds derived dependency views from the Lean environment and tracking state.

Key types:

- `InformalDeclDependencyEntry`
- `InformalReferenceDependencyEntry`

Key functions:

- `allInformalDeclDependencyEntries`
- `informalDeclDependencyEntry?`
- `informalDeclDependencyLeaves`
- `allInformalReferenceDependencyEntries`
- `informalReferenceDependencyEntry?`
- `informalReferenceDependencyLeaves`

Important semantics:

- declaration dependencies are computed transitively from `ConstantInfo.getUsedConstantsAsSet`
- traversal continues through untracked declarations
- public outputs only mention tracked declarations/references
- cycles are handled via a visited set

### `AFTK.Informal.Presentation`

Owns compact and rich presentation building and rendering.

Key types:

- `InformalPresentationSummary`
- `InformalBodyPresentation`
- `InformalPresentationPayload`
- `PresentationMode`
- `BodyRenderMode`

Key functions:

- `summaryOfResolved`
- `payloadOfResolved`
- `renderSummaryText`
- `renderPayloadText`
- `renderPresentationText`

Current body modes:

- `.none`
- `.preview`
- `.full`

The preview mode currently clips to a short deterministic preview and marks truncation explicitly.

### `AFTK.Informal.Elaborator`

Implements the actual `informal[...]` term elaborator.

Important behaviors:

- recovers the enclosing declaration name
- rejects pseudo-declaration contexts
- validates and resolves the node id
- elaborates explicit arguments normally
- creates a curried placeholder expression when arguments are present
- generates a site-unique tag with source-location information when available
- attaches a compact info-tree doc string
- records tracking only after successful elaboration steps

## Practical library usage

### Resolve a node explicitly

```lean
import AFTK.Informal

open AFTK.Informal

#eval do
  let ref ←
    match informalReferenceOfString? "group.basic.definition" with
    | .ok ref => pure ref
    | .error err => throw <| IO.userError err
  let result ← (resolveInformalReferenceAtRoot
    "tests/informal/knowledgebase-fixtures/basic-valid" ref).toIO'
  match result with
  | .ok resolved =>
      IO.println (renderSummaryText (summaryOfResolved resolved))
  | .error err =>
      IO.eprintln s!"{err.code}: {err.message}"
```

### Query tracking inside an imported environment

The tracking and dependency APIs are `CoreM` queries over an environment that must be imported with extension loading enabled.
That is why the informal CLI uses `Lean.importModules ... (loadExts := true)`.

In your own code, the same rule applies:

- import the modules whose tracking data you want
- run `CoreM` against that environment
- do not use import paths that skip extension loading if you want tracking state

## Behavioral details worth knowing

### One declaration, one deduplicated reference set

If a declaration repeats the same reference multiple times, the public row contains one copy of that reference.
This is by design.

### Reference dependencies are projected, not canonical

`InformalReferenceDependencyEntry` does not represent a separate persisted graph.
It is computed by projecting declaration dependencies through tracked declaration/reference associations.

### Knowledge-base metadata remains authoritative

Presentation uses knowledge-base metadata and body text as the source of truth.
The informal layer does not copy that data into its persistent tracking state.

## Layer boundary with the knowledge base

The most important boundary to preserve in downstream code is:

- knowledge-base code owns canonical prose and metadata
- informal code owns Lean-facing bridge behavior and declaration tracking

If you are adding higher-level features, prefer building on these APIs rather than inventing a second node-resolution or tracking scheme.
