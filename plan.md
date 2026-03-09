# aftk roadmap

## Purpose

This file is the current high-level roadmap for `aftk`.
It complements the implementation docs under `docs/` and the more detailed design notes under `plans/`.

Use the repository docs this way:

- `README.md` — project overview and quick start
- `docs/` — implementation that exists today
- `plan.md` — current roadmap and deferred work
- `plans/` — detailed component plans, design rationale, and some historical research context

## Current state

The repository currently has four implemented layers:

1. **Knowledge base**
2. **Informal bridge layer**
3. **Server / file-worker layer**
4. **TypeScript toolkit / pi integration layer**

The planned fifth layer is still **not implemented**:

5. **AI autoformalization / orchestration layer**

So the project is already a working Lean-core-plus-toolkit foundation, but it is not yet the full intended stack.

## Architectural commitments

The roadmap continues to assume these core architectural choices:

- the **knowledge base** is the single source of truth for canonical prose and metadata
- the **informal layer** is the Lean-facing bridge to knowledge-base nodes
- the **server / file-worker layer** provides interactive Lean queries and tactic exploration over real files
- the **toolkit layer** wraps those lower-layer public interfaces into reusable Node- and agent-facing clients and tools
- the later **AI layer** should build on the toolkit first, while still being free to call lower-layer CLIs directly when that is the better fit

In dependency order, the stack is:

```text
AFTK.KnowledgeBase
        ↓
AFTK.Informal
        ↓
AFTK.Server / AFTK.FileWorker
        ↓
TypeScript toolkit
        ↓
AI autoformalization / orchestration layer
```

## What is intentionally complete enough for v1

These areas now have real implementation and dedicated docs:

- knowledge-base storage, validation, search, relationships, and CLI
- knowledge-base-backed `informal[...]` elaboration, tracking, dependencies, presentation, and CLI
- hub/worker server executables, interactive queries, tactic exploration, and richer informal hover
- Node-compatible toolkit runtime, managed server client, CLI-backed knowledge-base/informal clients, tool families, pi adapters, and `aftk_setup`

Those layers still have deferred follow-ons, but they are no longer design-only.

## Main remaining roadmap items

### 1. AI autoformalization / orchestration layer

This is the largest missing layer.
It should eventually provide:

- agent workflows that combine Lean/server, knowledge-base, and informal tools
- planning, iteration, and proof-search orchestration
- handoff from transient tactic exploration to real source edits
- higher-level autoformalization strategies on top of the existing toolkit

This work should be built on the implemented toolkit and lower-layer public interfaces rather than reintroducing ad hoc wrappers.

### 2. Knowledge-base indexing

The knowledge base currently works directly from canonical storage and direct scans.
That is correct for v1, but the roadmap still includes optional derived indexing for:

- faster inventory-style queries
- faster incoming-relationship queries
- eventual search acceleration

Any indexing should remain derived and rebuildable, never canonical.

### 3. Knowledge-base repair tooling

Validation exists today, but repair remains deferred.
Future work should focus on conservative, validation-driven repair flows such as:

- rebuilding derived internal state
- normalizing already-valid manifests/metadata
- quarantining or explicitly handling malformed canonical files
- avoiding silent destructive edits

### 4. Toolkit expansion beyond the initial query-first surface

The toolkit is implemented, but its initial scope is intentionally conservative outside the Lean/server family.
Likely follow-ons include:

- selected mutation/admin wrappers for the knowledge-base CLI
- any future broader informal admin/query coverage that is worth exposing from TypeScript
- carefully designed composite helpers that combine multiple lower-layer calls without becoming the full AI layer

The toolkit should continue to wrap lower-layer public interfaces rather than becoming a second owner of semantics.

### 5. Possible server evolution

The current server model is a deliberate one-shot, reopen-on-change design.
Future work may revisit:

- richer editable-document support
- stronger diagnostics/progress integration
- request cancellation improvements
- additional structured result surfaces where higher layers actually need them

This is follow-on work, not a prerequisite for the current toolkit or lower layers.

## Current implementation boundaries

A few important limits are still deliberate:

- there is no AI orchestration layer yet
- knowledge-base indexing is not implemented
- knowledge-base repair tooling is not implemented
- the server does not yet provide an incremental editable-document model
- toolkit knowledge-base/informal coverage is intentionally query-first in v1

These boundaries are part of the current design, not documentation gaps.

## Near-term priorities

If the project is being advanced from the current state, the practical order should be:

1. keep `docs/` aligned with the implemented four-layer foundation
2. keep `plan.md` aligned with the actual deferred roadmap
3. use `plans/` for detailed component-level design work before larger follow-on changes
4. build the AI/orchestration layer on top of the toolkit rather than bypassing it
5. add indexing, repair, or broader toolkit/server follow-ons only when they unlock real workflows

## Documentation policy

Going forward, the repository should keep this split explicit:

- update `docs/` when implementation changes
- update `plan.md` when roadmap priorities or deferred areas change
- update `plans/` when component-level design rationale or detailed status changes

Generated artifacts and fixtures should stay outside the manual-doc-edit path:

- `.pi/APPEND_SYSTEM.md` is generated by `lake run aftk_setup`
- Markdown under `tests/**` is primarily fixture data

## Summary

`aftk` now has a real four-layer implementation foundation:

- knowledge base
- informal bridge
- server / file worker
- toolkit / pi integration

The main remaining work is the AI autoformalization layer, with indexing, repair, and selected follow-on expansion still intentionally deferred.
