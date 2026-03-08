# Server Integration with the Knowledge-Base and Informal Layers

## Status

Component plan and implementation-status document for how the server/file-worker layer should integrate with the knowledge-base and informal layers.
This document refines the overall server-layer plan in `plans/server.md` and works together with `plans/server/transport.md`, `plans/server/protocol.md`, `plans/server/hub.md`, `plans/server/worker.md`, `plans/server/lean-integration.md`, `plans/server/layout.md`, and `plans/server/testing.md`.

## Component implementation status

- Overall status: Implemented
- Implemented in code: Yes
- Last updated basis: the worker now preserves ordinary Lean hover, reuses existing informal-layer APIs, and produces richer preview-style hover for recognized `informal[...]` sites without adding new first-class lower-layer RPC methods.

## Purpose

This document defines how the server/file-worker layer should become aware of the rewrite’s lower layers without duplicating their responsibilities.
It focuses especially on:

- hover and info-view enrichment
- reuse of existing informal-layer presentation and resolution APIs
- the boundary between Lean-facing server methods and lower-layer library calls
- and the rule that canonical knowledge-base data remains owned by the knowledge-base layer

## Design goals

Integration at this layer should:

- make lower-layer information visible through the Lean-facing interactive surface where it materially helps users and tools
- reuse `AFTK.KnowledgeBase` and `AFTK.Informal` libraries instead of rebuilding their semantics inside the worker
- avoid introducing a second canonical store or long-lived duplicate caches
- preserve a small v1 public protocol rather than mirroring every lower-layer CLI command as RPC immediately
- build on the lower-layer presentation work already implemented in the rewrite

## Scope and non-scope

### In scope

- how hover/info queries should reuse lower-layer information
- which lower-layer APIs the worker should call directly
- whether v1 adds first-class lower-layer server methods
- temporary caching rules inside a worker snapshot

### Out of scope

- knowledge-base storage layout and mutation logic
- the internals of `informal[...]` elaboration and declaration tracking
- CLI design for the lower layers
- the file-worker’s generic Lean query mechanics

## Core integration decisions

The v1 integration strategy should make the following choices explicit.

### 1. Keep the public server protocol Lean-centric in v1

The v1 server should **not** add separate public RPC methods like:

- `kb_show_node`
- `kb_query`
- `informal_present`

or similar lower-layer command mirrors.

Instead, v1 integration should happen mainly by enriching the existing Lean-facing methods, especially:

- `get_hover`
- `get_infoview`

This keeps the first server implementation focused and avoids turning the server into a second general-purpose knowledge-base service before the core Lean workflow is in place.

### 2. Reuse lower-layer library APIs as the source of truth

The server layer should call into:

- `AFTK.KnowledgeBase`
- `AFTK.Informal`

for data and presentation logic.

It should not:

- read node files directly as ad hoc JSON/Markdown blobs,
- define its own alternate informal-reference model,
- or duplicate canonical metadata ownership.

### 3. Preserve the informal layer’s existing compact hover behavior

The rewrite’s informal elaborator already attaches compact presentation summaries to info trees through `docString?`/delab info.
The server/file-worker layer should preserve and test that behavior.

This is the minimum lower-layer-aware hover integration expected in v1.

### 4. Add richer worker-side informal hover enrichment when the syntax at the queried site clearly identifies an `informal[...]` reference

When the cursor is on a recognizable `informal[...]` occurrence, the worker should be able to do more than merely echo the elaboration-time compact summary.
The worker should attempt to recover the referenced node id from the syntax at the queried site and then reuse informal-layer presentation APIs to produce richer hover text.

This richer hover is still derived from lower-layer libraries, not from server-owned duplicate state.

### 5. Do not duplicate canonical lower-layer state inside long-running server state

The worker may keep transient caches such as:

- resolved rich presentation text for one file snapshot,
- or per-node rendering results,

but only as derived snapshot-local caches.
They must not become a second source of truth.

## Knowledge-base integration policy

The knowledge-base layer remains the owner of canonical node content and metadata.
The server layer should therefore treat the knowledge base as:

- a reusable library dependency,
- not a side directory to parse on its own.

### Allowed server-layer use of knowledge-base APIs

Examples of appropriate use include:

- resolving a known informal node reference
- rendering hover/presentation content derived from a resolved node
- reading metadata/body through the existing knowledge-base storage APIs indirectly via the informal layer

### Disallowed server-layer shortcuts

Examples of inappropriate use include:

- hand-reading node `.json` and `.md` files from the worker
- storing a parallel long-lived index of all nodes inside the server layer
- redefining knowledge-base validation or search semantics in server-specific code

## Informal-layer integration policy

The informal layer is the owner of the Lean↔knowledge-base bridge for `informal[...]` references.
The server layer should therefore use it as its main lower-layer integration point.

Relevant existing APIs already include:

- `AFTK.Informal.informalReferenceOfString?`
- `AFTK.Informal.resolveInformalReference`
- `AFTK.Informal.summaryOfResolved`
- `AFTK.Informal.payloadOfResolved`
- `AFTK.Informal.renderSummaryText`
- `AFTK.Informal.renderPayloadText`
- `AFTK.Informal.renderPresentationText`

The server layer should build on those rather than inventing its own rendering logic.

## Hover enrichment policy

Hover is the main place where lower-layer integration should show up in v1.

## Baseline behavior

For any ordinary Lean site, the worker should continue to use its normal Lean hover pipeline.
That includes the compact informal summary already attached to info trees by the informal elaborator when applicable.

## Richer behavior for `informal[...]` sites

When the queried syntax stack clearly identifies an `informal[...]` occurrence, the worker should:

1. recover the raw bracketed node id from syntax
2. validate it through `AFTK.Informal.informalReferenceOfString?`
3. resolve it through `AFTK.Informal.resolveInformalReference`
4. render richer deterministic hover text through informal-layer presentation helpers

### Recommended rich hover mode

For v1, the worker should prefer:

- `PresentationMode.rich`
- with `BodyRenderMode.preview`

That gives richer context than the compact elaboration-time summary while avoiding dumping full node bodies into routine hover.

## Precedence rule

When the worker positively identifies an `informal[...]` site and can render rich informal presentation successfully, that rich informal presentation should take precedence over the generic hover text for that term site.

Reasons:

- it avoids duplicating a compact summary plus a richer version of the same content
- it gives the server layer a predictable integration point
- and it makes the lower-layer-aware behavior an explicit part of the worker rather than an accident of generic hover selection

If rich presentation resolution fails unexpectedly, the worker should fall back to the ordinary Lean hover result rather than failing the whole hover request.

## `get_infoview` policy

`get_infoview` should incorporate the same hover integration policy as `get_hover`.
That means the hover slot inside `InfoViewResult` should already reflect the lower-layer-aware hover decision.

## Goal/tactic methods

The lower-layer integration in v1 should **not** change the semantics of:

- `load_node`
- `get_goals`
- `run_tactic`
- `run_tactic_steps`

Those remain Lean proof-state operations.
If later tooling needs first-class knowledge-base-aware tactic helpers, that should be a separate design step.

## Configuration and root resolution

The worker should reuse the same lower-layer configuration conventions that the informal layer already uses.
In particular, if the environment/options specify an explicit informal knowledge-base root (for example through the informal layer’s existing option), the worker’s richer hover integration should honor that rather than inventing a second root-discovery scheme.

## Caching policy

The worker may cache lower-layer-derived presentation results inside one worker snapshot if profiling shows that repeated hover over the same site or node is expensive.

Any such cache must obey these rules:

- it is derived only, never canonical
- it is scoped to one worker process / one file snapshot
- it is discarded when the worker exits or the file is reopened
- correctness must not depend on the cache being populated

A simple first implementation may reasonably skip caching altogether.

## Why not add first-class lower-layer RPC methods in v1?

Because the server layer’s first job is to provide a solid long-running Lean-facing operational surface.
That includes:

- file lifecycle
- hover/info queries
- transient tactic-state exploration

Mirroring lower-layer CLIs into the server immediately would broaden the scope without yet proving which long-running lower-layer APIs higher layers truly need.

The design should therefore follow this sequence:

1. integrate lower-layer information into existing Lean-facing methods
2. observe higher-layer needs
3. only then add first-class lower-layer RPC methods if they provide clear value

## Future extension points

Likely future extensions include:

- a structured hover payload that separates Lean hover text from lower-layer presentation blocks
- a dedicated server query for “present the informal node at this source location” if higher layers need structured data rather than plain text
- deeper use of informal tracking/ dependency APIs for declaration-level summaries

Those are plausible, but not required for the first server-layer implementation.

## Additional implementation findings from the current informal layer

Research in `AFTK/Informal/Elaborator.lean`, `AFTK/Informal/References.lean`, and `AFTK/Informal/Presentation.lean` makes the worker-side integration path quite concrete.

- The existing option for knowledge-base-root override is exactly `aftk.informal.root : String`.
- The elaborator resolves references through `resolveInformalReference ref root?`, where `root?` comes from the trimmed option value; the server should honor the same option rather than inventing its own root lookup.
- Compact hover data is already attached during elaboration as a `DelabTermInfo` with:
  - elaborator field `AFTK.Informal.elabInformalTermWithRef`
  - `docString?` set from `renderSummaryText summary`
- That means ordinary Lean hover over an `informal[...]` site already has a lower-layer-aware baseline even before any worker-specific enrichment is added.
- The validation and resolution pipeline the worker should reuse is already explicit:
  - `informalReferenceOfString?`
  - `resolveInformalReference` / `resolveInformalReferenceAtRoot`
  - `summaryOfResolved`
  - `payloadOfResolved`
  - `renderSummaryText`
  - `renderPayloadText`
  - `renderPresentationText`
- `AFTK.Informal.Presentation` sorts tags, authors, relationship lines, and Lean-reference lines before rendering, so the richer presentation path is intentionally deterministic and well suited to stable tests.
- `renderPresentationText resolved .rich .preview` is the most direct way to obtain the currently intended rich-preview text behavior already discussed elsewhere in these plans.

One practical implementation rule follows from this research.

- Failure to resolve richer worker-side hover should normally fall back to ordinary Lean hover, because the elaboration-time compact summary is already attached to the info tree and remains a good minimum behavior.

## Implementation guidance for the next code phase

The first code added for this plan should likely be:

- a worker-side helper that detects `informal[...]` syntax at a source location
- recovery of the referenced node id through existing informal syntax/reference helpers
- rich preview rendering through `AFTK.Informal.Presentation`
- fallback to ordinary Lean hover when no informal site is identified or rich rendering fails

That gives immediate value while preserving clear ownership boundaries.

## Completion checklist for this plan

This component plan should count as implemented only when all of the following are true in the rewrite worktree:

- the server layer reuses lower-layer library APIs rather than direct ad hoc file reads
- hover over ordinary Lean sites continues to work through the normal Lean query path
- hover over `informal[...]` sites preserves at least the existing compact informal summary behavior
- the worker can render richer preview-style informal hover content at recognized `informal[...]` sites
- no first-class lower-layer RPC methods have been added without an explicit later design decision
- any lower-layer-derived caches remain clearly worker-local and non-canonical

## Summary

The rewrite’s server layer should integrate with the lower layers primarily by enriching the existing Lean-facing interactive surface, especially hover.
It should reuse the already-implemented informal reference and presentation libraries, preserve compact elaboration-time hover summaries, and add richer preview-style presentation at recognized `informal[...]` sites—without turning the server into a duplicate knowledge-base service.
