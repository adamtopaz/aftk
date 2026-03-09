# Informal Placeholder Design

## Status

Component plan and implementation-status document for the informal-layer placeholder mechanism.
This document refines the overall informal-layer plan in `plans/informal.md` and works together with `plans/informal/elaboration.md`, `plans/informal/references.md`, `plans/informal/tracking.md`, `plans/informal/presentation.md`, `plans/informal/layout.md`, and `plans/informal/testing.md`.

## Component implementation status

- Overall status: Implemented (initial v1)
- Implemented in code: Yes
- Last updated basis: repository now defines the placeholder primitive in `AFTK.Informal.Placeholder` and exercises it through elaboration and direct-fixture tests.

## Purpose

This document defines the core placeholder mechanism used by `informal[...]` elaboration.
It explains:

- what the placeholder term is for
- what Lean-level constant or axiom shape it should have
- why it should be parameterized by a unique tag and a result type
- what definitional and unification behavior it should have
- where the soundness boundary lies
- what assumptions later layers may make about replacing or detecting placeholders

The placeholder mechanism is the part of the informal layer that actually lets Lean elaborate an unfinished term while preserving a bridge to informal planning state.

## Design goals

The placeholder mechanism should:

- support the current gradual-formalization workflow of writing typed placeholders inside declarations and proofs
- be extremely small and explicit at the kernel boundary
- make unsoundness obvious rather than hidden
- preserve per-occurrence distinctness through tags
- work uniformly at any universe level
- avoid encoding knowledge-base content into kernel terms unnecessarily
- avoid adding reduction behavior that would make placeholders act like real definitions
- be easy for later tooling to detect conceptually

## Scope and non-scope

### In scope

- the core Lean constant/axiom shape used by `informal[...]`
- universe polymorphism requirements
- the meaning of the `tag` parameter
- the meaning of the result-type parameter
- definitional equality and reduction expectations
- the soundness status of declarations that depend on placeholders
- expectations for future placeholder elimination or detection

### Out of scope

- term syntax and parsing
- knowledge-base reference parsing and resolution
- declaration-level occurrence tracking structures
- hover/info rendering
- CLI command design
- full acceptance-gate policy for higher workflow layers

Those belong to companion docs.

## Reference point from the main-worktree implementation

The current main-worktree design uses a single axiom:

```lean
axiom Informal.{u} (tag : Lean.Name) (alpha : Sort u) : alpha
```

This is small, explicit, and effective.
The elaborator constructs terms of the form:

```text
Informal tag α
```

or, when explicit arguments are written after `informal[...]`,

```text
Informal tag (A₁ → ... → Aₙ → R) a₁ ... aₙ
```

The rewrite should preserve this overall shape unless a clearly better alternative appears.
At present, no better alternative is identified.

## Core role of the placeholder

The placeholder is not the informal reference itself.
The placeholder is the **Lean term-level inhabitant** that allows elaboration to proceed.

Conceptually, `informal[node.id]` does two things at once:

1. it links the source occurrence to a knowledge-base node through elaboration/tracking/presentation logic
2. it inserts an inhabitant of the expected Lean type through the placeholder mechanism

The placeholder handles only the second part.
It should stay minimal and not absorb bridge concerns that belong elsewhere.

## Proposed Lean-level design

The recommended v1 design is a single universe-polymorphic axiom in the informal-layer namespace:

```lean
namespace AFTK.Informal

/--
Unsound placeholder used during gradual formalization.
`tag` keeps different placeholder occurrences distinct.
-/
axiom Informal.{u} (tag : Lean.Name) (α : Sort u) : α

end AFTK.Informal
```

This should be the only kernel-level placeholder primitive needed for v1.

## Why use an axiom

An axiom is the right default design here because it is:

- explicit about unsoundness
- trivial to elaborate against
- universe polymorphic without extra machinery
- free of accidental computational behavior
- easy to reason about operationally

In particular, the use of an axiom makes it impossible to pretend that placeholder-backed declarations are ordinary proved Lean content.
That explicitness is a feature, not a drawback.

## Why keep the interface this small

The placeholder constant should take only:

- a unique tag
- a result type

and return an inhabitant of that type.

This is intentionally minimal.
It avoids pushing bridge-specific information into kernel terms.

### What should not be added to the axiom interface

The placeholder should **not** take:

- a knowledge-base node id string
- copied node metadata
- markdown text
- summary text
- declaration names
- source-provenance objects
- tracking-state payloads

Those concerns belong in elaboration-time logic, environment extensions, or presentation structures.
They do not need to appear inside the kernel term.

## Why use `Lean.Name` for the tag

The recommended v1 tag type remains `Lean.Name`.
That is a good fit because:

- the current elaborator strategy already naturally produces `Name`-shaped tags
- `Lean.Name` is compact and well-supported in elaboration code
- tags are internal identity markers, not user-authored semantic ids
- the tag is not the knowledge-base reference, so it does not need the node-id grammar

This means the system should clearly distinguish:

- **reference identity**: a knowledge-base `NodeId`
- **placeholder identity**: a per-occurrence `Lean.Name` tag

Those are different concepts and should stay different.

## Universe polymorphism

The placeholder must work for arbitrary expected result universes.
That means the axiom should remain universe polymorphic:

```lean
Informal.{u} : Lean.Name → Sort u → Sort u
```

This is needed because `informal[...]` may appear in terms of many different types, including:

- propositions
- ordinary data types such as `Nat`
- function types
- dependent types at higher universes

The elaborator should infer the correct universe level from the expected result type, as described in `plans/informal/elaboration.md`.

## Placeholder construction model

The placeholder constant itself stays simple even when the user writes explicit term arguments after `informal[...]`.

If the elaborator sees:

```lean
informal[node.id] x y
```

and the argument types are `A` and `B` with expected result type `R`, the elaborator should build:

```text
Informal tag (A → B → R) x y
```

This means:

- the placeholder axiom itself is still just `Lean.Name → Sort u → α`
- function application behavior comes from elaboration wrapping the result type into a function type before applying arguments

The placeholder primitive therefore stays orthogonal to term-argument elaboration.

## Distinctness requirements

Different placeholder occurrences must remain distinct, even when they reference the same knowledge-base node.

### Required property

If two source occurrences are different, the elaborated placeholder terms should also be different terms.

### Recommended mechanism

This distinctness should come from the `tag` parameter, not from changing the placeholder constant itself.

### Consequence

These two occurrences should elaborate to different terms:

```lean
def a : Nat := informal[group.basic.definition]
def b : Nat := informal[group.basic.definition]
```

Likewise, two occurrences in the same declaration should still differ if they arise from different source positions.

The exact tag-generation strategy belongs primarily to `plans/informal/elaboration.md`, but the placeholder design depends on that strategy to preserve per-occurrence identity.

## Definitional equality and reduction behavior

The placeholder mechanism should have **no reduction rule**.

### Desired behavior

- `Informal tag α` should not reduce to any canonical value
- there should be no simp lemmas for it
- the kernel should treat it as an opaque axiom application
- two placeholders with different tags should not become definitionally equal by computation

This is important because placeholders are planning artifacts, not executable definitions.

## Unification expectations

Placeholders should participate in Lean type checking only through their declared type, not through special unification behavior.

### What should happen

- `Informal tag α` can inhabit `α`
- surrounding elaboration may use the expected type to determine `α`
- ordinary unification over the type parameter still happens

### What should not happen

- placeholders should not solve goals by computation
- placeholders should not expose hidden structure for unification
- the system should not try to compare placeholders semantically through their referenced node ids

In other words, the placeholder is type-correct but semantically inert.

## Soundness boundary

The placeholder mechanism is explicitly unsound.
That is the central fact users and higher layers must understand.

### Meaning of unsoundness here

If a declaration depends on `AFTK.Informal.Informal`, then that declaration is not a finished formal result in the usual sound Lean sense.

This affects:

- definitions containing placeholders
- theorem statements or proofs completed through placeholders
- any downstream declarations depending on those declarations

### Design intent

This unsoundness is acceptable because the placeholder is part of a gradual-formalization workflow.
It is not meant to represent final accepted mathematics.

### Required explicitness

The design should continue to present the placeholder as an axiom rather than trying to disguise it as an ordinary implementation detail.

## Relationship to the knowledge base

The placeholder primitive itself should remain independent of knowledge-base node contents.

### Important separation

- the reference layer and elaborator resolve a node id through the knowledge base
- the placeholder primitive merely produces an inhabitant of the expected type

This separation is important because it keeps the kernel term small and stable.
It also avoids duplicating natural-language data or metadata inside expressions.

## Why not bake node ids into the placeholder term

One tempting design would be something like:

```lean
axiom Informal.{u} (nodeId : String) (tag : Lean.Name) (α : Sort u) : α
```

This should be rejected for v1.

### Reasons to reject it

- it duplicates information already tracked outside the term
- it bloats the kernel term representation with bridge metadata
- it makes term equality sensitive to reference payloads that do not matter for type checking
- it encourages later code to inspect kernel terms for bridge data instead of using tracking structures

The node reference belongs in elaboration-time and environment-extension state, not in the placeholder primitive.

## Why not use `sorry`

The rewrite should not model `informal[...]` as merely reusing Lean’s built-in `sorry` mechanism.

### Reasons to reject `sorry` as the primary design

- `informal[...]` needs its own bridge semantics and tracking story
- the system needs explicit distinction between ordinary Lean `sorry` use and knowledge-base-linked placeholders
- the elaborator already needs custom reference resolution and presentation hooks
- a dedicated placeholder primitive keeps the informal layer conceptually clear

This does not prevent higher-level tooling from treating placeholders and `sorry` as related categories of unfinished work.
It only means the informal layer should own its own placeholder mechanism.

## Why not use an `opaque` definition

An `opaque` definition would still require some value on the right-hand side and would suggest a computational interpretation that the design does not actually have.
The intended semantics are simply “unsound inhabitant of any requested type,” which is exactly what the axiom expresses.

## Why not generate one fresh constant per occurrence

Another possible design would be to synthesize or declare a separate constant for every occurrence.
This should be rejected for v1.

### Reasons to reject it

- it complicates the environment model significantly
- it creates unnecessary declaration churn
- a single primitive plus a unique tag already provides the needed distinctness at term level
- it is harder to reason about operationally than one fixed placeholder primitive

## Detection and future elimination assumptions

A completed or acceptably formalized development should eventually eliminate these placeholders from the declarations that matter.

### Practical expectation

Over time, successful formalization should replace `informal[...]` occurrences with ordinary Lean terms and proofs.

### What higher layers may assume

Higher layers may reasonably assume that:

- placeholder-dependent declarations are provisional
- reducing the number of declarations depending on `AFTK.Informal.Informal` is meaningful progress
- a future validation or acceptance command may choose to report remaining placeholder dependencies

### What this design does not require yet

This document does not require a specific v1 command for placeholder detection.
It only establishes that such detection should be conceptually straightforward because the placeholder primitive is fixed and explicit.

## Recommended module boundary

A natural home for the primitive is a dedicated module such as:

```text
AFTK/Informal/Placeholder.lean
```

with a public namespace such as:

```lean
namespace AFTK.Informal
```

The placeholder primitive should be defined in a small module with no unnecessary dependencies.
In particular, it should not depend on:

- knowledge-base storage code
- CLI code
- tracking code
- presentation code

Those layers depend on the placeholder concept, not the other way around.

## Testing implications

The placeholder design should lead to tests that check at least the following:

- the primitive is universe polymorphic
- elaborated placeholder terms have the expected curried type shape
- different source occurrences produce different tagged terms
- placeholder terms do not reduce computationally
- declarations using placeholders can be detected conceptually by later analysis

The full test strategy belongs in `plans/informal/testing.md`, but these are the core behaviors to preserve.

## Rejected alternatives summary

The following alternatives should be rejected for v1:

- baking knowledge-base ids or metadata into the placeholder primitive
- using `Lean.Name`/`NodeId` reference identity as the placeholder tag itself
- replacing the dedicated primitive with generic `sorry`
- using an `opaque` definition instead of an explicit axiom
- generating one declared placeholder constant per source occurrence

## Lean 4 and current-implementation reuse findings

The current main-worktree placeholder design is already close to the minimal design the rewrite wants.
The main reusable idea is simply:

```lean
axiom Informal.{u} (tag : Lean.Name) (α : Sort u) : α
```

That design has several virtues the rewrite should preserve:

- minimal kernel surface area
- explicit unsoundness
- clean elaborator integration
- no redundant coupling to informal-content storage
- compatibility with source-position-derived uniqueness tags

Core Lean reinforces this direction in two ways:

- `Meta.mkLabeledSorry` also separates source-site identity from semantic payload by using a `Lean.Name` tag rather than baking rich metadata into the kernel term
- `SorryLabelView.encode`/`decode?` show that `Lean.Name` is a practical carrier for source-labelled occurrence identity without making that identity the actual external reference id

At present, there is no strong reason to change this shape for the rewrite.

## Open questions for companion docs

This document intentionally leaves nearby details to companion plans:

- Exact elaboration of `informal[...]` into applications of the placeholder primitive belongs in `plans/informal/elaboration.md`.
- How references are represented and resolved belongs in `plans/informal/references.md`.
- How placeholder-backed occurrences are recorded declaration-by-declaration belongs in `plans/informal/tracking.md`.
- How placeholder-backed terms should be surfaced in hover/info belongs in `plans/informal/presentation.md`.
- Testing details belong in `plans/informal/testing.md`.

## Summary

The rewrite should use a single explicit universe-polymorphic axiom as its placeholder primitive:

```lean
axiom AFTK.Informal.Informal.{u} (tag : Lean.Name) (α : Sort u) : α
```

This primitive should stay minimal: it should encode only a per-occurrence tag and the requested result type, with no knowledge-base ids, metadata, paths, or reduction behavior baked into the kernel term.

That keeps the soundness boundary obvious, preserves distinctness between placeholder occurrences, and cleanly separates the kernel-level placeholder mechanism from the knowledge-base-backed bridge logic handled elsewhere in the informal layer.
