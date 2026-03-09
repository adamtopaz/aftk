# Informal Elaboration Design

## Status

Component plan and implementation-status document for informal-layer elaboration.
This document refines the overall informal-layer plan in `plans/informal.md` and works together with `plans/informal/references.md`, `plans/informal/placeholder.md`, `plans/informal/tracking.md`, `plans/informal/presentation.md`, `plans/informal/layout.md`, `plans/informal/testing.md`, and the knowledge-base plans under `plans/knowledgebase/`.

## Component implementation status

- Overall status: Implemented (initial v1)
- Implemented in code: Yes
- Last updated basis: repository now elaborates bracketed `informal[...]` references against the knowledge base, attaches compact hover summaries, and records successful declaration-level occurrences.

## Purpose

This document defines how the rewrite’s `informal[...]` term elaboration should work.
It covers:

- supported syntax forms
- when those forms are allowed to elaborate
- how bracketed references resolve through the knowledge base
- how placeholder expressions are constructed
- how unique placeholder tags are generated
- how elaboration connects to tracking and presentation hooks
- what user-facing failures should look like

The goal is to preserve the useful workflow shape of the current main-worktree `Informalize` elaborator while changing the data source underneath it.
In the rewrite, bracketed informal references must resolve through the knowledge base rather than through `informal/...` sidecar files.

## Design goals

Elaboration for the informal layer should:

- preserve the current placeholder-driven Lean workflow
- keep `informal[...]` lightweight and predictable as a term elaborator
- require bracketed references to resolve through canonical knowledge-base data
- remain usable in ordinary declaration bodies and proofs
- produce distinct placeholders for distinct source occurrences
- register successful occurrences for later querying
- attach enough information for Lean-facing presentation such as hover/info views
- fail early and clearly when a referenced knowledge-base node cannot be resolved

## Scope and non-scope

### In scope

- term syntax for `informal[...]`
- elaboration-time validation and resolution of bracketed references
- construction of the placeholder expression returned by the elaborator
- site-unique tag generation requirements
- elaboration-time hooks into tracking and presentation
- user-facing error behavior

### Out of scope

- the exact bracketed-reference type and parser beyond what elaboration needs
- the detailed design of the placeholder axiom/constant itself
- persistent environment extension structure beyond the elaboration hook points
- the exact hover/info rendering format
- CLI behavior
- full scaffold orchestration semantics

Those are covered by the companion component plans.

## Reference point from the main-worktree implementation

The current main-worktree elaborator in `../aftk/Informalize/Elaborator.lean` provides the behavior we are intentionally learning from.
Its key properties are:

- syntax forms:
  - `informal[Foo.bar]`
  - `informal[Foo.bar] x y`
  - `informal`
  - `informal x y`
- bracketed references are currently parsed as `ident` and resolved through `Informalize.LocationId`
- bracketed elaboration eagerly loads markdown plus effective metadata from `informal/...`
- the resulting term is built from an unsound placeholder axiom, with a unique tag and a function type inferred from the written arguments plus expected result type
- successful elaboration records an occurrence in a persistent environment extension
- bracketed elaboration also pushes hover/info data into the info tree
- use is rejected outside declaration/proof contexts

The rewrite should preserve most of that behavior shape.
The central changes are:

- the bracketed reference must resolve through `AFTK.KnowledgeBase`
- the elaborator must not read from an `informal/...` markdown/json sidecar store
- bare `informal` support should be removed in the rewrite

## High-level semantic model

The rewrite should preserve the idea that `informal[...]` is a **typed placeholder term**, not a quotation of markdown and not a parser for mathematical prose.

More precisely:

- `informal[node.id]` means “insert a placeholder here, and associate it with the knowledge-base node `node.id`”
- any explicit term arguments written after `informal[...]` are ordinary Lean term arguments to the placeholder
- the referenced node is used for:
  - existence/validity checking
  - traceability
  - later querying
  - presentation support
  - access to knowledge-base metadata already owned by the knowledge base
- the referenced node is **not** used to synthesize the Lean type of the placeholder in v1

So in v1, the knowledge-base node is a bridge target and documentation anchor, not a type-theoretic specification.

## Supported syntax forms

The v1 elaborator should support bracketed knowledge-base-backed placeholder forms such as:

```lean
informal[node.id]
informal[node.id] x
informal[node.id] x y
```

Bare `informal` should not be supported in the rewrite.

### Bracketed form

The bracketed form is the knowledge-base-backed bridge form.
It should remain term syntax rather than a command.

Recommended v1 surface syntax:

```lean
syntax (name := informalTermWithRef) "informal[" informalNodeId "]" (ppSpace term:max)* : term
```

where `informalNodeId` is a dedicated syntax/parser layer intended to accept the full knowledge-base node-id grammar directly rather than reusing Lean `ident` syntax as the contract.

## Why use the full node-id grammar directly

The rewrite should not make the surface meaning of bracketed informal references depend on Lean identifier syntax.
Instead, the bracketed payload should be parsed according to the knowledge-base node-id grammar itself.

Important clarification:

- the bracketed token should be interpreted as a knowledge-base node id directly
- it should not be treated as a Lean declaration name
- it should not be routed through a `Lean.Name`-based location model
- it should accept whatever node-id grammar the knowledge-base layer defines as canonical for references

This keeps the informal layer aligned with the knowledge base as the authority on node identity.

## Context restrictions

The elaborator should only succeed in ordinary declaration-value or proof contexts where there is a meaningful enclosing declaration name.

### Allowed contexts

Typical supported examples:

```lean
def foo : Nat := informal[group.basic.definition]

def bar (x : α) : β :=
  informal[translation.note] x

theorem baz : P := by
  exact informal[proof.sketch]
```

### Rejected contexts

The elaborator should reject use in command-generated pseudo-declaration contexts such as:

- `#check ...`
- `#eval ...`
- `_check`
- `_reduce`
- `_synth_cmd`
- similar command-expansion contexts where no stable declaration occurrence should be recorded

The exact implementation of pseudo-context detection may evolve, but the user-facing rule should remain:

> `informal[...]` may only be used inside declaration values or proofs.

### Rationale

This matches the main-worktree behavior and keeps occurrence tracking anchored to real declarations rather than ephemeral command contexts.

## Elaboration pipeline

The elaborator should follow a pipeline close to the current implementation, but with knowledge-base resolution in place of sidecar loading.

### Step 1: parse the bracketed reference form

On entry, the elaborator should extract the bracketed node-id payload and pass it to the reference-resolution layer.

### Step 2: require a valid declaration context

The elaborator should query the current declaration name.
If there is no valid enclosing declaration, it should fail immediately with a clear message.

### Step 3: resolve the bracketed reference

The elaborator should:

1. convert the parsed reference token into the informal-layer reference type
2. validate it as a knowledge-base node id
3. resolve it through reusable knowledge-base APIs
4. load enough canonical node information to confirm the node is usable and to support later presentation hooks

### Step 4: elaborate explicit arguments normally

Each explicit argument written after `informal[...]` should be elaborated as an ordinary term.
The elaborator should not inject special expected types for those arguments.

### Step 5: determine the placeholder result type

The elaborator should use the expected type supplied by Lean when one is available.
If none is available, it should create a fresh type metavariable and allow surrounding elaboration constraints to solve it later.

### Step 6: build the placeholder function type

If the written arguments elaborate to expressions with inferred types:

- `A₁`, `A₂`, ..., `Aₙ`

and the expected result type is `R`,
then the placeholder constant should be instantiated at the curried function type:

```text
A₁ → A₂ → ... → Aₙ → R
```

At the expression level this should be represented as nested `forall`/function binders exactly as in ordinary Lean function types.

### Step 7: generate a site-unique placeholder tag

The elaborator should generate a tag that is unique to the source occurrence.
This tag must distinguish multiple informal placeholders even when:

- they reference the same knowledge-base node id, or
- they occur in the same declaration

### Step 8: construct the placeholder expression

The elaborator should apply the placeholder constructor to:

- the generated unique tag
- the placeholder function type

and then apply the resulting function to the elaborated explicit arguments.

### Step 9: attach presentation info for bracketed forms

If reference resolution succeeded, the elaborator should push enough info-tree data for later Lean-facing presentation.
This is where hover/info rendering can recover the linked knowledge-base context.

### Step 10: record the occurrence

After successful elaboration, the elaborator should record the occurrence in the informal-layer tracking extension.

### Step 11: synthesize and instantiate metavariables

Before returning, the elaborator should synthesize synthetic metavariables and instantiate any solved metavariables so that failures are surfaced promptly and the returned expression is as resolved as practical.

## Expected-type behavior

Expected-type handling should stay simple and close to normal Lean term elaboration.

### Rule 1: use the provided expected type when available

If Lean already knows the expected type of the whole `informal[...]` term, the elaborator should use that type as the result type of the placeholder.

### Rule 2: otherwise introduce a fresh result-type metavariable

If no expected type is provided, the elaborator should create a fresh type metavariable and let surrounding constraints determine it if possible.

### Rule 3: do not infer result type from knowledge-base content in v1

The elaborator should **not** attempt to infer the result type from:

- node kind
- markdown text
- metadata fields
- declaration names embedded in the knowledge base

That would mix the bridge layer with higher-level semantic interpretation that is out of scope for v1.

### Consequence

`informal[node.id]` remains a placeholder with ordinary Lean expected-type behavior.
The node reference adds traceability and presentation context, not a type synthesis oracle.

## Argument handling

Explicit term arguments should work exactly as they do in the main-worktree elaborator.

### Rule 1: elaborate arguments independently as terms

Each written argument after `informal` should be elaborated as a normal term.

### Rule 2: placeholder becomes a curried function over those arguments

If the user writes:

```lean
informal[node.id] x y
```

and the inferred argument types are `A` and `B`, with expected result type `R`,
then the placeholder constant should be instantiated at a type equivalent to:

```text
A → B → R
```

and then applied to `x` and `y`.

### Rule 3: no special argument semantics in v1

The elaborator should not treat the explicit arguments as:

- citation parameters
- substitutions into markdown text
- proof obligations extracted from the node body

They are just ordinary Lean arguments to a placeholder term.

## Reference resolution requirements

Bracketed elaboration should depend on reusable informal-layer and knowledge-base library APIs rather than on ad hoc file access.

### What resolution must establish

For a bracketed reference, resolution must establish at least that:

- the reference parses as a valid knowledge-base node id
- the referenced node exists in canonical knowledge-base storage
- the node can be loaded through the knowledge-base library
- the node is not malformed in a way that makes it unusable as a linked informal node

### What elaboration should load

Elaboration should load only enough information to support:

- successful existence/validity checking
- attachment of a compact presentation summary at the term site
- tracking of the referenced node id
- access to the node metadata already owned by the knowledge base

The recommended v1 policy is:

- load the canonical node and its metadata through the knowledge-base library
- derive at most a compact summary suitable for hover/info attachment
- defer full body rendering and richer content loading to hover/query time

The exact rendering shape is defined in `plans/informal/presentation.md`.

### What elaboration should not do

Elaboration should not:

- scan the whole knowledge base
- perform search/ranking
- invent fallback ids
- read from a separate `informal/...` path convention
- load full linked body content during ordinary elaboration unless that later becomes strictly necessary for presentation correctness
- silently create missing nodes

## Placeholder construction

The elaborated term should preserve the current conceptual shape:

- there is one universe-polymorphic placeholder constructor
- it takes a unique tag and a result type
- it yields an inhabitant of that type

At the expression level, the result should follow the current main-worktree pattern:

```text
Informal tag (A₁ → ... → Aₙ → R) a₁ ... aₙ
```

where `Informal` names the informal-layer placeholder constructor defined by the companion placeholder design.

### Examples

With no explicit arguments:

```lean
def foo : Nat := informal[group.basic.definition]
```

should elaborate like:

```text
Informal tag Nat
```

With one explicit argument:

```lean
def foo (x : α) : β := informal[group.basic.definition] x
```

should elaborate like:

```text
Informal tag (α → β) x
```

## Unique tag generation

Distinctness of placeholders is a key requirement.
Two different occurrences must not collapse merely because they share the same referenced node id.

### Tag requirements

A generated tag should satisfy the following:

- different source occurrences should get different tags
- the source-labelled part of the tag should be stable when practical, even if the final `Lean.Name` includes fresh macro scopes for uniqueness
- tag generation should not depend on the referenced node body text
- two occurrences in the same declaration should still receive distinct tags

### Recommended strategy

The recommended v1 strategy is to derive tags primarily from source-location information, reusing the current main-worktree approach as much as practical.
A good implementation basis is:

- current module name
- source range of the syntax occurrence
- an encoding method similar to `SorryLabelView.encode`

In Lean core, `SorryLabelView.encode` packages the source location into a `Lean.Name`-shaped label and then passes it through `mkFreshUserName`.
So the resulting tag is best thought of as:

- source-labelled after erasing macro scopes, and
- uniqueness-preserving in actual elaboration.

That is a good fit for the informal layer as well.

### Fallback behavior

If precise source-position data is unavailable, the elaborator should fall back to a uniqueness-preserving strategy rather than failing.
The fallback does not need to be perfectly stable across rebuilds, but it must still preserve per-occurrence distinctness.

## Tracking hook requirements

Successful elaboration should register an occurrence with the informal-layer tracking subsystem.

### Bracketed occurrence

For `informal[node.id]`, the tracking hook should receive at least:

- the enclosing declaration name
- the resolved node id

### Declaration-level tracking policy

The public tracking surface for the informal layer should remain declaration-level.
That means the elaborator may report successful uses at individual term sites, but the tracked result exposed to later tooling should collapse to declaration-level information rather than becoming a per-site public API.

### Timing rule

Tracking should happen only after successful elaboration and successful bracketed reference resolution.
A failed resolution should not leave behind a partial tracked occurrence.

The detailed tracked data model is defined in `plans/informal/tracking.md`.

## Presentation hook requirements

Bracketed elaboration should attach info-tree metadata so Lean-facing tools can surface linked knowledge-base context at the term site.

### Minimum requirement

At minimum, the attached info should make it possible for hover-like tooling to display:

- the referenced node id
- a compact summary derived from the knowledge-base node and its metadata

Full body rendering and richer linked content should be deferred to hover/query time rather than eagerly attached at every elaboration site.

The exact presentation decision belongs to `plans/informal/presentation.md`.

## User-facing error behavior

Elaboration errors should be early, explicit, and tied to the bracketed reference site when possible.

### Invalid context

If used outside an allowed declaration/proof context, the error should say that `informal[...]` may only be used inside declaration values or proofs.

### Invalid bracketed reference

If the bracketed token does not correspond to a valid knowledge-base node id, the error should be reported at the bracketed reference and should explain the validation failure.

### Missing node

If the node id is valid but no canonical knowledge-base node exists for it, elaboration should fail at that reference and should name the missing node id.

### Malformed or unusable node

If the knowledge-base library cannot load the node or the node fails required validation, elaboration should fail with a message that names:

- the node id
- the reason the node could not be used

### Type errors

If surrounding type inference fails, those failures should surface through ordinary Lean elaboration errors rather than through a bespoke `informal`-specific error layer.

## Design decisions for v1

The following decisions are recommended for the first rewrite implementation:

1. Support bracketed `informal[...]` only; remove bare `informal` support.
2. Parse bracketed references using the full knowledge-base node-id grammar directly rather than Lean `ident` syntax.
3. Treat bracketed payloads as knowledge-base node ids, not Lean declaration names.
4. Resolve bracketed references eagerly through the knowledge-base library during elaboration.
5. Preserve the current curried-placeholder treatment of explicit term arguments.
6. Keep result-type inference driven by Lean expected types, not by knowledge-base content.
7. Keep placeholder tags unique per source occurrence, not per node id.
8. Expose declaration-level tracking rather than a per-site public tracking surface.
9. Load only enough knowledge-base data during elaboration to validate the node and attach a compact summary; defer richer content to hover/query time.

## Lean 4 and current-implementation reuse findings

The current main-worktree elaborator already demonstrates several Lean mechanisms that the rewrite should likely reuse.

Useful implementation pieces include:

- `@[term_elab ...]` term elaborators for bracketed informal-reference syntax
- `Term.getDeclName?` to recover the surrounding declaration name from `TermElabM`
- an explicit pseudo-context filter on top of `getDeclName?`, since Lean still uses declaration names such as `_check`/`_reduce`/`_synth_cmd` for command-generated contexts
- `withRef` and `throwErrorAt` for precise user-facing error locations
- `elabTerm arg none` for ordinary explicit-argument elaboration
- `Meta.inferType` plus `instantiateMVars` for argument/result-type handling
- `mkForall` to build the curried placeholder function type
- `Meta.getLevel` to instantiate the universe-polymorphic placeholder constructor
- `mkAppN` to apply the placeholder to explicit arguments
- `Term.synthesizeSyntheticMVarsNoPostponing` to surface unresolved synthetic obligations promptly
- `Elab.pushInfoLeaf` and `DelabTermInfo` as a practical basis for hover/info integration
- `SorryLabelView.encode` as a source-location-driven tag template, with the caveat that it adds fresh macro scopes via `mkFreshUserName` and therefore gives stronger uniqueness guarantees than strict textual tag stability

The rewrite should reuse these Lean mechanisms where they still fit, while changing only the reference-resolution/data-loading part to go through `AFTK.KnowledgeBase`.

## Open questions for companion docs

This document intentionally leaves some nearby questions to companion plans:

- The exact bracketed reference type and parsing helpers belong in `plans/informal/references.md`.
- The exact placeholder constant or axiom belongs in `plans/informal/placeholder.md`.
- The tracked occurrence schema belongs in `plans/informal/tracking.md`.
- The exact hover/info rendering contract belongs in `plans/informal/presentation.md`.
- Root/module layout and imports belong in `plans/informal/layout.md`.
- Test matrices and fixtures belong in `plans/informal/testing.md`.

## Summary

The rewrite’s elaboration design should preserve the practical meaning of `informal[...]` as a typed placeholder term with optional explicit arguments, declaration-anchored tracking, and Lean-facing presentation support.

The key architectural changes are that bracketed references must resolve through the knowledge base rather than through `informal/...` sidecar files, and that bare `informal` support should be dropped.
That keeps the rewrite aligned with the knowledge base as the sole canonical store of natural-language content while preserving the useful gradual-formalization workflow shape of the current main-worktree elaborator.
