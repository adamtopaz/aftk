# Informal Reference Design

## Status

Component plan and implementation-status document for informal-layer references.
This document refines the overall informal-layer plan in `plans/informal.md` and works together with `plans/informal/elaboration.md`, `plans/informal/placeholder.md`, `plans/informal/tracking.md`, `plans/informal/presentation.md`, `plans/informal/layout.md`, `plans/informal/testing.md`, and the knowledge-base plans under `plans/knowledgebase/`.

## Component implementation status

- Overall status: Implemented (initial v1)
- Implemented in code: Yes
- Last updated basis: repository now implements `InformalReference`, `ResolvedInformalReference`, and exact knowledge-base-backed resolution helpers in `AFTK.Informal.References`.

## Purpose

This document defines the reference model for bracketed informal references such as:

```lean
informal[group.basic.definition]
```

It explains:

- what a bracketed informal reference denotes
- how bracketed payloads should be parsed and validated
- how the informal layer should represent references in Lean code
- how references resolve through the knowledge-base library
- how this replaces the main-worktree `LocationId` + `informal/...` sidecar-path scheme
- what does and does not belong in the informal-layer reference object itself

The core architectural point is simple:

> A bracketed informal reference is a reference to a knowledge-base node.

It is not a Lean declaration name, not a filesystem path, and not a separate informal-layer content id.

## Design goals

The informal reference design should:

- make knowledge-base node identity the sole authority for bracketed informal references
- keep the syntax-to-reference mapping explicit and predictable
- avoid introducing a second id system for informal content
- avoid duplicating path logic already owned by the knowledge base
- avoid duplicating metadata already owned by the knowledge base
- support exact, deterministic resolution through reusable knowledge-base APIs
- give elaboration, tracking, presentation, and CLI code a stable shared reference type
- keep user-facing error behavior clear when a reference is malformed or unresolved

## Scope and non-scope

### In scope

- the conceptual meaning of `informal[...]` bracket payloads
- the syntax-level contract for accepted node-id text
- the validated Lean-level reference type
- the resolved-reference type used after knowledge-base lookup
- the relationship between informal references and `KnowledgeBase.NodeId`
- the replacement of the main-worktree `LocationId` model
- exact-match resolution semantics through the knowledge-base library

### Out of scope

- the full term elaboration pipeline
- the placeholder axiom/constant design
- persistent occurrence tracking structure
- hover/info rendering details
- CLI command design
- full root-discovery and process-configuration policy for every consumer

Those belong to companion design docs.

## Reference point from the main-worktree design

The current main-worktree `Informalize` design uses `LocationId` values such as:

- `Foo.bar`
- `Foo.bar.baz`

Those ids are:

- validated through a `Lean.Name`-oriented model
- constrained to have at least two components
- mapped directly to sidecar files under `informal/...`
- given helper methods such as:
  - `markdownPath`
  - `metadataPath`
  - `readMarkdown`

That model is useful as a reference point, but it is the wrong abstraction for the rewrite.
The rewrite’s informal layer must not define its own content-store path scheme.

The key replacement is:

- old meaning: bracket payload identifies an `informal/...` sidecar location
- new meaning: bracket payload identifies a `knowledgebase/nodes/...` node through `KnowledgeBase.NodeId`

## Core design decision

The informal layer should treat bracketed informal references as thin semantic wrappers around knowledge-base node ids.

That means:

- the knowledge base owns the canonical id grammar
- the knowledge base owns path mapping for those ids
- the knowledge base owns node loading and validation
- the informal layer only adds the fact that a given node id is being used as an informal/formal bridge target inside Lean

So the reference model should be **knowledge-base-native**, not sidecar-native and not `Lean.Name`-native.

## Conceptual stages of a reference

It is useful to distinguish three stages.

### 1. Raw bracket payload

This is the syntax-level text written by the user inside:

```lean
informal[...]
```

At this stage it is just parsed text.
It is not yet a validated reference.

### 2. Validated informal reference

This is the semantic informal-layer reference object created after the bracket payload has been validated as a canonical knowledge-base node id.

At this stage we know:

- the text satisfies the knowledge-base node-id grammar
- the informal layer can treat it as a stable id value

But we do not yet necessarily know that the node exists on disk.

### 3. Resolved informal reference

This is the result of taking a validated informal reference and resolving it through the knowledge-base library.

At this stage we know:

- the node exists in canonical knowledge-base storage
- the node could be loaded
- the node is usable for elaboration/presentation/tracking purposes

This distinction keeps parsing, validation, and storage lookup conceptually separate.

## Proposed Lean-level types

The informal layer should use a thin wrapper around `AFTK.KnowledgeBase.NodeId` rather than using raw strings throughout.

A good v1 shape is:

```lean
namespace AFTK.Informal

structure InformalReference where
  nodeId : AFTK.KnowledgeBase.NodeId
  deriving Repr, DecidableEq, Inhabited, BEq, Hashable

structure ResolvedInformalReference where
  ref : InformalReference
  storedNode : AFTK.KnowledgeBase.StoredNode

end AFTK.Informal
```

### Why wrap `NodeId` at all?

A dedicated wrapper is useful even though it contains only a `NodeId` initially.
It gives the codebase:

- semantic clarity in APIs
- room for future bridge-specific helpers without polluting `KnowledgeBase.NodeId`
- a clear type distinction between “any knowledge-base node id” and “a node id being used as an informal bridge reference”

### What should *not* go in `InformalReference`

The reference object itself should **not** store:

- a duplicate markdown path
- a duplicate metadata path
- copied node metadata fields
- copied node body text
- declaration-tracking state
- presentation-rendering text

Those belong either to the knowledge base or to later bridge stages.

## Rendering and equality

The rendering and equality behavior of `InformalReference` should be driven entirely by the underlying `NodeId`.

### Equality

Two informal references are equal iff their underlying `nodeId` values are equal.

### Ordering

If ordering is needed for deterministic output, it should delegate to the underlying `NodeId` ordering.

### String rendering

The human-facing rendered form should be the canonical node-id string, for example:

- `group.basic.definition`
- `topology.open_cover`

### JSON rendering

If the informal layer serializes references in JSON for CLI or tooling use, the default external representation should be the canonical node-id string, reusing the `NodeId` JSON form where practical.

## Surface syntax contract

Bracketed informal references should use the canonical knowledge-base node-id grammar directly.
They should not be constrained by Lean `ident` syntax as the semantic contract.

The intended surface form is:

```lean
informal[<node-id>]
```

where `<node-id>` is parsed according to the same grammar the knowledge base accepts for `NodeId`.

## Node-id grammar for bracketed references

At the current knowledge-base design level, the authoritative grammar is the `NodeId` grammar already defined by the knowledge-base layer.
That currently means:

- the id is nonempty
- it consists of one or more dot-separated segments
- it does not begin or end with `.`
- it has no empty segments
- it contains no path separators
- it contains no whitespace
- each segment begins with a lowercase ASCII letter
- remaining segment characters are lowercase ASCII letters, digits, or `_`

Examples that should be accepted under the current grammar include:

- `group`
- `group.basic`
- `group.basic.definition`
- `topology.open_cover`
- `analysis.uniform_continuity`

Examples that should be rejected include:

- `Foo.bar`
- `.group.basic`
- `group.basic.`
- `group..basic`
- `group/basic`
- `group.basic theorem`
- `3group.basic`

### Important consequence

Unlike the old `LocationId` scheme, informal references should **not** impose an extra “at least two components” rule.
If the knowledge-base layer allows a one-segment `NodeId`, then `informal[group]` should be a valid reference at the reference-model level.

## Parsing strategy

The syntax layer should introduce a dedicated parser/category for bracketed node ids rather than reusing Lean `ident` as the contract.

A good v1 direction is:

```lean
declare_syntax_cat informalNodeId
syntax ... : informalNodeId
syntax (name := informalTermWithRef) "informal[" informalNodeId "]" (ppSpace term:max)* : term
```

The exact parser implementation may vary, but the design intent should be:

- parse exactly the character language intended for knowledge-base node ids
- preserve a direct route from syntax text to `NodeId`
- avoid accidental reliance on `Lean.Name` parsing behavior

Lean core already provides a useful precedent for this style of design: `Lean.Json` uses its own `declare_syntax_cat ... (behavior := symbol)` rather than pretending JSON literals are ordinary Lean identifiers or terms.
The informal node-id payload can follow the same philosophy as a small embedded sublanguage.

Implementation-wise, two parser shapes are both acceptable so long as validation still flows through `NodeId.ofString?`:

- a single atom-like payload syntax whose exact raw text can later be recovered with `Syntax.getAtomVal`, or
- a segmented syntax tree that is reassembled into dotted text before validation.

### Authoritative validation rule

Even if the parser rejects obviously malformed payloads early, the authoritative semantic validation step should still call the knowledge-base validator, currently `AFTK.KnowledgeBase.NodeId.ofString?`.

That prevents the informal layer from drifting away from the actual knowledge-base rules.

## Why not reuse `Lean.Name` or `ident`

The rewrite should reject the old location-id-oriented interpretation.

### Problems with `Lean.Name`

A `Lean.Name`-based interpretation would:

- tie the reference model to Lean declaration-name conventions
- encourage thinking of the bracket payload as a Lean name rather than a knowledge-base node id
- make the informal layer responsible for a name model the knowledge base does not own

### Problems with plain `ident`

Using `ident` as the semantic contract would:

- overfit the informal layer to Lean parser categories
- admit or reject inputs for Lean-specific reasons rather than knowledge-base-specific reasons
- make future node-id grammar evolution harder if it ever diverges from `ident`

The informal layer should therefore parse bracket payloads according to the knowledge-base grammar directly.

## Resolution semantics

Resolution of an informal reference should be exact and deterministic.

### Exact-match lookup only

A validated `InformalReference` should resolve only by exact `NodeId` match.
The resolver should not perform:

- prefix matching
- fuzzy matching
- alias lookup
- search/ranking
- path guessing
- lazy node creation

This keeps reference semantics simple and predictable.

### Recommended resolution shape

At a high level, resolution should:

1. obtain an initialized knowledge-base context or storage root
2. resolve that root through reusable knowledge-base storage/path APIs
3. load the referenced node exactly by its `NodeId`
4. return a `ResolvedInformalReference` containing the validated reference and the loaded stored node

### Recommended knowledge-base reuse points

Given the current rewrite code, the most natural implementation path is to reuse existing knowledge-base APIs such as:

- `AFTK.KnowledgeBase.NodeId.ofString?`
- `AFTK.KnowledgeBase.PathLayout.resolveRootPath`
- `AFTK.KnowledgeBase.Storage.resolveInitializedRoot`
- `AFTK.KnowledgeBase.Storage.loadStoredNode`

The informal layer should build on those APIs rather than duplicating validation or file loading logic.

## Root and context handling

The reference object itself should be root-independent.
An `InformalReference` is just a validated node-id wrapper.

Resolution, however, needs a knowledge-base context.

### Recommended boundary

The reference design should keep this split:

- `InformalReference` does not know where the knowledge base lives
- resolver functions accept either:
  - an explicit initialized knowledge-base context, or
  - an explicit root/config object from which that context can be built

This avoids baking current-working-directory assumptions into the reference type itself.

### Important non-goal

The informal layer should not introduce its own separate root-discovery semantics for informal references.
If root resolution defaults exist, they should reuse the knowledge-base layer’s path/layout policy rather than inventing an `informal/`-specific convention.

## Relationship to storage and path layout

The informal layer should never compute canonical markdown/json paths for references on its own.

### What the informal layer should do

- keep the semantic reference as a node id
- ask the knowledge-base layer to resolve and load the node
- use loaded node/path information only after resolution has happened

### What the informal layer should not do

It should not define reference methods like:

- `markdownPath`
- `metadataPath`
- `readMarkdown`
- `readMetadata`

on the informal reference type itself.

Those were appropriate in the old sidecar-backed `LocationId` design.
They are not appropriate when the knowledge base is the canonical store.

## Metadata ownership

The informal layer should not define a second metadata schema for bracketed informal references.

### Rule

All content metadata associated with a referenced informal node should come from the knowledge-base node metadata.

### Consequences

This means:

- there is no informal-reference-local `kind`
- there is no informal-reference-local `status`
- there is no informal-reference-local `parent`
- there is no informal-reference-local `tags`
- there is no informal-reference-local `knowledgeRefs`

If such information is needed while elaborating or rendering a reference, it should be obtained from the resolved knowledge-base node.

### What the informal layer may still own

This does **not** forbid the informal layer from owning bridge-specific state elsewhere, such as:

- declaration-level occurrence tracking
- declaration-to-node linkage indexes
- derived dependency projections
- presentation caches

It only means that the reference object itself should not become a duplicate metadata store.

## Error behavior

The reference layer should distinguish clearly between:

### Parse/validation failure

The bracket payload does not satisfy the knowledge-base node-id grammar.
This should produce a validation error pointing at the bracket payload.

### Resolution failure: missing node

The id is valid, but no canonical knowledge-base node exists for it.
This should produce a not-found style error naming the missing node id.

### Resolution failure: malformed node

The id is valid and the node files exist, but the knowledge-base layer cannot load the node successfully.
This should surface as a load/validation error that still names the referenced node id.

These distinctions matter because they correspond to different user actions:

- fix the reference text
- create the missing node
- repair the malformed knowledge-base node

## Rejected alternatives

The following designs should be rejected for the rewrite.

### 1. Reuse `Informalize.LocationId` directly

Rejected because it bakes in the old sidecar-path model and `Lean.Name`-style constraints.

### 2. Use raw `String` everywhere

Rejected because it loses validation discipline and makes APIs ambiguous.

### 3. Use filesystem paths as the reference identity

Rejected because paths are a storage realization, not the canonical semantic id.
The knowledge base already establishes `NodeId` as the canonical identity.

### 4. Use `ident` as the lasting semantic contract

Rejected because it makes Lean parser categories, rather than the knowledge-base design, the authority on reference syntax.

### 5. Copy selected node metadata into the reference object

Rejected because it duplicates canonical knowledge-base metadata and risks divergence.

## Lean 4 and current-library reuse findings

The rewrite already has most of the core machinery needed for this design in the knowledge-base layer.

Useful reuse points include:

- `AFTK.KnowledgeBase.NodeId` as the underlying canonical id type
- `AFTK.KnowledgeBase.NodeId.ofString?` as the authoritative validator
- `AFTK.KnowledgeBase.PathLayout.nodeIdToRelativeStem` and related helpers for storage-derived reasoning when needed after resolution
- `AFTK.KnowledgeBase.Storage.resolveInitializedRoot` for obtaining a usable storage context
- `AFTK.KnowledgeBase.Storage.loadStoredNode` for exact node loading
- `ToJson`/`FromJson`, `ToString`, hashing, and ordering behavior already defined for `NodeId`
- Lean syntax categories with `behavior := symbol`, as used by core embedded syntaxes such as `Lean.Json`, as a good precedent for a dedicated node-id sublanguage
- `Syntax.getAtomVal` as a straightforward way to recover exact payload text if the parser chooses an atom-like representation for the bracket contents

The informal layer should lean on these rather than rebuilding them.

## Open questions for companion docs

This document intentionally leaves some nearby implementation details to companion plans:

- The exact term-syntax/elaboration pipeline belongs in `plans/informal/elaboration.md`.
- The placeholder mechanism belongs in `plans/informal/placeholder.md`.
- Declaration-level tracked occurrence structure belongs in `plans/informal/tracking.md`.
- Presentation payload shape belongs in `plans/informal/presentation.md`.
- Module boundaries and resolver/context plumbing belong in `plans/informal/layout.md`.
- Parser and resolution test cases belong in `plans/informal/testing.md`.

## Summary

Bracketed informal references in the rewrite should be thin, validated wrappers around `AFTK.KnowledgeBase.NodeId` values.
They should be parsed according to the knowledge-base node-id grammar directly, resolved by exact match through reusable knowledge-base APIs, and never treated as `Lean.Name` values or as paths into a separate `informal/...` sidecar store.

This keeps the informal layer aligned with the knowledge base as the sole authority for natural-language node identity, storage, and metadata, while still giving the Lean-side bridge a clear and explicit reference model.
