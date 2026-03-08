# Informal Presentation Design

## Status

Component plan and implementation-status document for informal-layer presentation.
This document refines the overall informal-layer plan in `plans/informal.md` and works together with `plans/informal/elaboration.md`, `plans/informal/references.md`, `plans/informal/tracking.md`, `plans/informal/cli.md`, `plans/informal/layout.md`, and `plans/informal/testing.md`.

## Component implementation status

- Overall status: Implemented (initial v1)
- Implemented in code: Yes
- Last updated basis: rewrite worktree now implements compact and rich presentation builders/renderers in `AFTK.Informal.Presentation` and attaches compact summaries to info trees during elaboration.

## Purpose

This document defines how knowledge-base-backed `informal[...]` references should be presented to users and tools.
It covers:

- what information should appear at an `informal[...]` term site
- what should be attached eagerly during elaboration
- what richer content should be deferred to hover/query time
- what presentation shapes should be available for Lean-facing tooling
- how presentation should relate to knowledge-base metadata ownership
- how presentation should degrade when rich rendering is unavailable

The key design clarification already settled in `plans/informal.md` is:

> Elaboration should load only the minimum linked knowledge-base information needed to validate the reference and attach a compact presentation summary; richer body/content rendering should be deferred to hover/query time.

This document turns that clarification into a concrete presentation policy.

## Design goals

The presentation layer should:

- make `informal[...]` references intelligible at the point of use in Lean
- preserve the main-worktree benefit that hover can surface linked informal context
- avoid eager loading and embedding of full knowledge-base content at every elaboration site
- derive presentation from canonical knowledge-base content rather than duplicating it
- provide a compact summary that is cheap and reliable enough for routine hover use
- support richer content on demand when query infrastructure is available
- stay deterministic and readable for both humans and automation
- degrade gracefully if richer presentation plumbing is unavailable

## Scope and non-scope

### In scope

- Lean-facing presentation of `informal[...]` term sites
- compact summary rendering for elaboration-time attachment
- richer hover/query-time rendering policy
- formatting choices for metadata and body previews
- relationship between presentation payloads and canonical knowledge-base content
- fallback behavior when only compact presentation is available

### Out of scope

- reference parsing and validation
- placeholder kernel primitive design
- occurrence tracking state design
- declaration/reference dependency analysis
- CLI command-family design in detail
- file-worker/server protocol details beyond presentation expectations

Those belong to companion plans.

## Reference point from the main-worktree implementation

The current main-worktree `Informalize` implementation does something very direct:

- elaboration resolves the informal id
- elaboration eagerly loads the full markdown note and effective metadata
- elaboration pushes a `DelabTermInfo` leaf with a pre-rendered `docString?`
- ordinary hover tooling then surfaces that rendered text

The current hover text combines:

- the informal location id
- metadata origin
- a metadata summary block
- the full markdown note body

That design is effective and pleasant for small sidecar-backed notes.
However, the rewrite should change the eager-loading policy because:

- knowledge-base nodes are the canonical source now
- nodes may be richer and larger than the old sidecar notes
- the informal layer has already chosen to avoid eager full-body attachment during elaboration

So the rewrite should preserve the usefulness of hover while adopting a more staged presentation model.

## Core design decision

The rewrite should use a **two-tier presentation model**.

### Tier 1: compact presentation summary

This is the default presentation attached at elaboration time.
It should be:

- cheap to compute from already-loaded knowledge-base information
- small enough for routine hover use
- sufficient to orient the user to the referenced node

### Tier 2: richer on-demand presentation

This is the fuller presentation available when hover/query infrastructure can resolve or render more at request time.
It may include:

- more metadata details
- a body preview or full body
- optional relationship or Lean-reference sections

This richer layer should be loaded/rendered only when needed, not attached eagerly to every term site.

## What presentation is for

Presentation is not a second storage system and not a second metadata model.
Its job is to expose, in a Lean-friendly way, information already owned canonically by the knowledge base.

That means presentation should be thought of as:

- a transient view over a referenced node
- rendered for the convenience of Lean users and tools
- reconstructible from the node id plus knowledge-base state

It should not become a place where canonical content is rewritten or maintained separately.

## Primary presentation surfaces

The informal layer should care about at least two presentation surfaces.

### 1. Term-site Lean hover/info presentation

This is the main surface.
When the cursor or query lands on an `informal[...]` occurrence, Lean-facing tooling should be able to show at least a compact summary of the referenced node.

This is the direct rewrite successor to the current main-worktree hover behavior.

### 2. Explicit query-time presentation

Some tools may want richer node presentation than what is practical to attach eagerly at elaboration time.
Examples include:

- AFTK/file-worker hover integrations with additional resolution support
- explicit informal-layer query commands
- agent-facing tooling that asks for a node summary or body at a specific site

The presentation design should support this richer query-time rendering without forcing it into the elaboration-time path.

## Compact summary content

The compact summary should be enough to orient the user quickly at the term site.

### Required fields

The compact summary should always include:

- the referenced node id
- a display title

### Recommended fields

When available, the compact summary should also include:

- node kind
- node status
- metadata summary text

### Optional fields

The compact summary may also include, if they are cheap and helpful:

- a small tag list
- a small author list

But these should remain secondary and should not crowd out the core summary.

## Compact summary source of truth

The compact summary should be derived from knowledge-base node data already loaded through normal resolution.

### Recommended metadata reuse

The most useful compact-summary fields map naturally to the current knowledge-base metadata model:

- node id -> `NodeMetadata.id`
- display title -> `NodeMetadata.title` or `NodeMetadata.titleOrId`
- kind -> `NodeMetadata.kind`
- status -> `NodeMetadata.status`
- summary -> `NodeMetadata.summary?`

### Important rule

The informal layer should not define replacement fields like:

- informal title
- informal kind
- informal status
- informal summary

The knowledge base already owns that information.

## Proposed compact-summary type

A good v1 view model is:

```lean
namespace AFTK.Informal

structure InformalPresentationSummary where
  ref : InformalReference
  title : String
  kind? : Option AFTK.KnowledgeBase.NodeKind := none
  status? : Option AFTK.KnowledgeBase.NodeStatus := none
  summary? : Option String := none
  deriving Repr, Inhabited

end AFTK.Informal
```

### Why this shape is useful

- it is small and explicit
- it contains only presentation-relevant view data
- it does not duplicate full node bodies or arbitrary metadata blobs
- it is easy to render in both text and JSON-oriented contexts

This type should be treated as a transient derived view, not as canonical stored state.

## Rich presentation content

Richer presentation should build on the compact summary rather than replacing it.

### Recommended rich fields

A richer presentation view may include:

- everything in the compact summary
- tags, if nonempty
- authors, if nonempty
- a body preview or full body
- optional relationship summary counts or selected relationship lines
- optional Lean-reference summary if useful and nonempty

### Default restraint

The rich presentation should still avoid dumping every field unconditionally.
If optional sections are empty, they should normally be omitted.

## Body rendering policy

The body is often the most useful part of the referenced node, but it is also the part most likely to become too large for routine hover.
So the presentation layer needs an explicit policy.

## Recommended body modes

The presentation layer should conceptually support three body modes.

### 1. No body

Used for compact elaboration-time summaries.
Only metadata-based orientation is shown.

### 2. Preview body

Used for ordinary richer hover/query presentation.
A fixed-size excerpt of the Markdown body is shown.

### 3. Full body

Used only when explicitly requested, or when the body is small enough that showing it fully remains reasonable.

## Default policy for ordinary hover-like rich presentation

The recommended v1 policy for ordinary rich hover-like presentation is:

- show the full body if it is small
- otherwise show a clearly marked preview and indicate truncation

### Why this policy

It preserves much of the convenience of the current main-worktree hover experience without turning every hover into an unbounded dump of node content.

### Threshold policy

The exact thresholds can be finalized in implementation/testing, but v1 should use a fixed default truncation rule such as:

- a line limit, and/or
- a character limit

with explicit truncation markers.

The exact numeric threshold need not be frozen in this design doc, but it should be deterministic and testable.

## Formatting policy

Presentation output should be structured and easy to scan.

## Recommended compact text layout

A compact term-site summary should render roughly like:

```text
Informal node: group.basic.definition
Title: Definition of group
Kind: definition
Status: active
Summary: A group is a monoid in which every element has an inverse.
```

### Compact rendering rules

- always include the node id line
- always include a title line, using `titleOrId` behavior if needed
- include kind/status lines when available
- include summary only when nonempty
- omit empty optional sections rather than printing `(none)` repeatedly

## Recommended rich text layout

A richer presentation should keep a stable header and then add optional sections.
A reasonable shape is:

```text
Informal node: group.basic.definition
Title: Definition of group
Kind: definition
Status: active
Summary: A group is a monoid in which every element has an inverse.

Tags
----
- algebra
- basic

Body
----
... preview or full markdown body ...
```

### Optional sections

The rich presentation may add sections such as:

- `Tags`
- `Authors`
- `Relationships`
- `Lean refs`
- `Body`

but only when they are nonempty and genuinely helpful.

## Structured presentation for tools

Even though Lean hover is primarily text-oriented, the informal layer should still think in terms of structured view models first and rendered strings second.

### Recommendation

The presentation module should expose structured summary/payload builders and small renderers on top of them.

That makes it easier to support:

- hover text
- CLI text output
- CLI JSON output
- future server/toolkit integration

without duplicating formatting logic everywhere.

## Proposed richer payload type

A reasonable v1 transient payload is:

```lean
namespace AFTK.Informal

inductive InformalBodyPresentation
  | none
  | preview (text : String) (truncated : Bool)
  | full (text : String)
  deriving Repr, Inhabited

structure InformalPresentationPayload where
  summary : InformalPresentationSummary
  tags : Array String := #[]
  authors : Array String := #[]
  relationshipLines : Array String := #[]
  leanRefLines : Array String := #[]
  body : InformalBodyPresentation := .none
  deriving Repr, Inhabited

end AFTK.Informal
```

This should remain a derived presentation payload, not a persisted object.

## Elaboration-time attachment policy

The elaborator should attach enough information for term-site presentation, but should not be forced to attach the full rich payload eagerly.

### Recommended v1 policy

At elaboration time:

- resolve the reference through the knowledge base
- construct an `InformalPresentationSummary`
- attach a compact rendered summary to the info tree

### Richer content

Richer payload construction should be deferred until a later hover/query path explicitly asks for it, where the infrastructure supports that.

## Lean info-tree integration

The rewrite should preserve the current high-level integration strategy of attaching presentation information to Lean’s info tree.

### Recommended baseline

A practical v1 baseline is:

- attach a `DelabTermInfo` or equivalent hoverable info leaf
- provide at least a compact summary `docString?`

This is attractive because it aligns with the current main-worktree approach and works with existing hoverable-info plumbing.
Lean core’s server-side hover path already makes this especially practical:

- `Info.docString?` checks explicit `DelabTermInfo.docString?` first, and
- `Info.fmtHover?` appends that docstring to the ordinary hover block.

So a compact rendered summary is enough to participate in standard Lean hover without custom widget machinery in v1.

## Best-effort richer integration

If the surrounding Lean/AFTK integration later supports richer query-time re-resolution cleanly, the presentation layer should also support:

- taking a tracked or resolved informal reference
- rebuilding a richer `InformalPresentationPayload` on demand
- rendering that richer payload for hover/query responses

### Important fallback rule

The baseline compact summary should not depend on this richer machinery existing.
The compact presentation path must stand on its own.

## Graceful degradation policy

Presentation is important, but it should not be allowed to destabilize successful elaboration once the reference has already resolved.

### Recommended rule

After a reference has been validated and resolved successfully:

- failure to build nonessential rich presentation should degrade to a smaller presentation payload
- failure to attach optional presentation details should not invalidate the successfully elaborated term

### Minimal fallback

The final fallback should still be able to show at least:

- `Informal node: <id>`

This ensures that even degraded presentation preserves the identity of the referenced node.

## Relationship to tracking and references

Presentation should consume the products of the reference and tracking layers without duplicating their responsibilities.

### Reference layer responsibility

- identify and resolve the referenced node

### Tracking layer responsibility

- record declaration↔reference linkage

### Presentation layer responsibility

- turn a resolved node or tracked reference + current knowledge-base state into a readable view

This separation keeps the layers compositional.

## Relationship to the knowledge base

The knowledge base remains the owner of canonical content and metadata.
Presentation should therefore treat itself as a derived view layer.

### Presentation should not persist

- copied node bodies
- copied metadata snapshots
- copied path data as canonical presentation state

### Presentation may derive

- title-oriented summaries
- tag/author display lists
- relationship summary lines
- body previews or truncation decisions

All of these are derived from current knowledge-base state.

## Relationship to AFTK/file-worker hover

The rewrite should preserve the useful current workflow where AFTK hover at an `informal[...]` term can surface linked informal context.

### Recommended expectation

At minimum, AFTK/file-worker hover over an `informal[...]` occurrence should surface the compact presentation summary.

### Preferred richer behavior

If the surrounding integration can resolve richer payloads at request time, AFTK/file-worker hover should be able to surface:

- the compact summary header
- a body preview or full body according to the configured policy
- selected additional metadata sections when useful

This keeps the Lean-facing workflow valuable for both humans and agents.

## Error behavior

Presentation rendering should distinguish between:

### Reference-resolution failure

This is not really a presentation error.
It is an elaboration/reference error and should already have failed before presentation is attempted.

### Rich-rendering degradation

This happens when compact summary construction succeeded but optional richer rendering cannot be completed cleanly.
In that case the system should fall back to a smaller view rather than turning a successful elaboration into a failure.

### Empty optional sections

This is not an error.
It should simply lead to omitted sections in the rendered output.

## Determinism requirements

Presentation should be deterministic given the same resolved node and the same rendering mode.

### Required determinism points

- field order in rendered summaries should be fixed
- optional sections should appear in a fixed section order when present
- truncation policy should be deterministic
- relationship and Lean-ref lines should be rendered in deterministic order if shown

This matters for:

- predictable hover behavior
- testing
- agent consumption of rendered outputs

## Testing implications

The presentation design should lead to tests that check at least the following:

- compact summaries always include node id and title
- compact summaries omit empty optional fields cleanly
- rich payload rendering includes body previews/full body according to policy
- truncation is explicit and deterministic
- presentation can be built from resolved knowledge-base nodes without duplicating canonical metadata ownership
- fallback rendering still produces a minimal useful summary
- field and section ordering remain stable

The full test strategy belongs in `plans/informal/testing.md`, but these are the core presentation invariants.

## Rejected alternatives

The following alternatives should be rejected for v1:

### 1. Eagerly attach the full node body at every elaboration site

Rejected because the design has already chosen to keep elaboration-time loading small and defer richer content to hover/query time.

### 2. Define a second informal-layer metadata schema just for presentation

Rejected because the knowledge base already owns metadata.

### 3. Make ordinary presentation depend entirely on rich lazy re-resolution machinery

Rejected because the compact presentation path should remain reliable even if richer query-time integration is unavailable.

### 4. Render every metadata field unconditionally in hover output

Rejected because it would make ordinary presentation noisy and hard to scan.

### 5. Treat knowledge-base paths as primary presentation content

Rejected because path layout is a storage concern, not the main Lean-facing user presentation.

## Lean 4 and current-implementation reuse findings

The current main-worktree implementation already demonstrates a practical baseline:

- use `DelabTermInfo`
- push an info leaf during elaboration
- let ordinary hover plumbing surface the attached `docString?`

The rewrite should likely reuse that baseline for compact summaries.

Core Lean confirms that this is not a hacky side path but the normal hover path:

- `Info.docString?` prefers an explicit `DelabTermInfo.docString?` when one is present
- `Info.fmtHover?` appends that docstring to the usual pretty-printed term/module hover content
- `Elab.pushInfoLeaf` is enough to place such a leaf into the info tree during elaboration

Useful knowledge-base reuse points include:

- `NodeMetadata.titleOrId`
- `NodeMetadata.kind`
- `NodeMetadata.status`
- `NodeMetadata.summary?`
- the node body when richer preview/full rendering is requested

This gives the presentation layer a clean path to derive its views without inventing new ownership boundaries.

## Open questions for companion docs

This document intentionally leaves nearby details to companion plans:

- The exact elaboration hook that attaches compact presentation belongs in `plans/informal/elaboration.md`.
- The exact resolved-reference type belongs in `plans/informal/references.md`.
- CLI commands exposing richer presentation belong in `plans/informal/cli.md`.
- Module layout and helper placement belong in `plans/informal/layout.md`.
- Fixture and hover-integration tests belong in `plans/informal/testing.md`.

## Summary

The rewrite should use a two-tier presentation model for `informal[...]`:

- a compact elaboration-time summary suitable for ordinary Lean hover, and
- a richer on-demand presentation that can include body previews or full body content when query-time infrastructure supports it.

Both tiers should be derived from canonical knowledge-base data rather than from a separate informal-layer content store or metadata schema. The compact path should always be reliable and cheap, while richer rendering should be deferred, bounded, and gracefully degradable.
