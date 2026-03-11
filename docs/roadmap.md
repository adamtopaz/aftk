# aftk roadmap

This document describes the project-level vision and the main deferred work for `aftk`.
It complements `docs/architecture.md`, which focuses on the implementation that exists today.

## Project vision

`aftk` is intended to be a full stack for Lean-oriented autoformalization and AI-assisted proof workflows.
The long-term architecture has four layers:

1. **Knowledge base**
2. **Informal bridge layer**
3. **Server / file-worker layer**
4. **AI autoformalization / orchestration layer**

The first three layers provide the reusable foundation.
The fourth layer is the missing piece that will eventually turn that foundation into higher-level agent workflows for planning, proof search, editing, and coordination between Lean state and canonical informal knowledge.

## Core architectural commitments

The project continues to assume these core design choices:

- the **knowledge base** is the single source of truth for canonical prose and structured metadata
- the **informal layer** is the Lean-facing bridge to knowledge-base nodes
- the **server / file-worker layer** provides interactive Lean queries and transient tactic exploration over real files
- future higher-level automation should build on stable lower-layer public interfaces rather than duplicating their semantics

In dependency order, the intended stack is:

```text
AFTK.KnowledgeBase
        ↓
AFTK.Informal
        ↓
AFTK.Server / AFTK.FileWorker
        ↓
AI autoformalization / orchestration
```

## Current implementation state

The repository already implements the first three layers:

- **Knowledge base** — canonical Markdown + JSON storage, validation, search, relationships, and a CLI
- **Informal** — `informal[...]` elaboration, declaration-level tracking, dependency views, presentation, and a CLI
- **Server / file worker** — standalone JSON-RPC executables for Lean queries, richer hover, and transient tactic exploration

The planned fourth layer is still **not implemented**:

- **AI autoformalization / orchestration** — higher-level agent workflows built on top of the lower layers

## Intentional current boundaries

A few important limits are still deliberate parts of the current design:

- there is no AI orchestration layer yet
- knowledge-base indexing is not implemented
- knowledge-base repair tooling is not implemented
- the server still uses a one-shot, reopen-on-change model rather than an incremental editable-document model

These are current product boundaries, not documentation gaps.

## Main roadmap items

### 1. AI autoformalization / orchestration layer

This is the largest remaining area.
It should eventually provide:

- workflows that combine Lean/server, knowledge-base, and informal capabilities
- planning, iteration, and proof-search orchestration
- handoff from transient tactic exploration to real source edits
- higher-level autoformalization strategies built on the implemented lower-layer public interfaces

This layer should build on the existing repository interfaces rather than reintroducing ad hoc parallel semantics.

### 2. Knowledge-base indexing

The knowledge base currently works directly from canonical storage and direct scans.
That is correct for the current implementation, but future work may add optional derived indexing for:

- faster inventory-style queries
- faster incoming-relationship queries
- eventual search acceleration

Any index should remain derived and rebuildable, never canonical.

### 3. Knowledge-base repair tooling

Validation exists today, but repair remains deferred.
Future repair work should stay conservative and validation-driven, for example by focusing on:

- rebuilding derived internal state
- normalizing already-valid manifests or metadata
- quarantining or explicitly handling malformed canonical files
- avoiding silent destructive edits

### 4. Possible server and interface evolution

The current server model is a deliberate one-shot, reopen-on-change design.
Possible follow-on work includes:

- richer editable-document support
- stronger diagnostics or progress integration
- request-cancellation improvements
- additional structured result surfaces where higher layers actually need them

This is follow-on work, not a prerequisite for the current foundation.

## Practical priorities

If the project is advanced from the current state, the practical order should be:

1. keep `docs/` aligned with the implemented three-layer foundation
2. keep `docs/roadmap.md` aligned with the actual deferred work and long-term direction
3. build the future AI layer on top of the lower-layer public interfaces rather than bypassing them
4. add indexing, repair, or server follow-ons only when they unlock concrete workflows

## Summary

`aftk` already has a real three-layer Lean foundation:

- knowledge base
- informal bridge
- server / file worker

The main missing piece is the AI autoformalization layer.
Beyond that, indexing, repair, and selected server/interface expansion remain intentionally deferred follow-ons.
