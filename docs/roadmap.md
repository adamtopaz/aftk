# aftk roadmap

This document describes the project-level vision and the main remaining work for `aftk`.
It complements `docs/architecture.md`, which focuses on the implementation that exists today.

## Project vision

`aftk` is intended to be a full stack for Lean-oriented autoformalization and AI-assisted proof workflows.
The long-term architecture has four layers:

1. **Knowledge base**
2. **Informal bridge layer**
3. **Server / file-worker layer**
4. **AI autoformalization / orchestration framework**

All four layers now exist in the repository.
The first three provide the more mature Lean/toolkit foundation.
The fourth layer now exists as an experimental Python framework built on top of that foundation.

## Core architectural commitments

The project continues to assume these core design choices:

- the **knowledge base** is the single source of truth for canonical prose and structured metadata
- the **informal layer** is the Lean-facing bridge to knowledge-base nodes
- the **server / file-worker layer** provides interactive Lean queries and transient tactic exploration over real files
- the **Python framework** should build on the existing lower-layer public interfaces rather than duplicating their semantics
- framework state should stay explicit and persistent under `.aftk/`, rather than living only in chat history
- deterministic Python code should own task-state mutation; agents should return structured proposals and reports

In dependency order, the intended stack is:

```text
AFTK.KnowledgeBase
        ↓
AFTK.Informal
        ↓
AFTK.Server / AFTK.FileWorker
        ↓
aftk_client
        ↓
experimental autoformalization framework
```

## Current implementation state

The repository already implements:

- **Knowledge base** — canonical Markdown + JSON storage, validation, search, relationships, and a CLI
- **Informal** — `informal[...]` elaboration, declaration-level tracking, dependency views, presentation, and a CLI
- **Server / file worker** — standalone JSON-RPC executables for Lean queries, richer hover, and transient tactic exploration
- **Experimental framework** — project snapshots, persistent task state, worker coding tools, `pydantic-ai` initializer/orchestrator/worker services, runner integration, telemetry/cost rollups, and `aftk-inspect`

So the main roadmap question is no longer whether the AI layer should exist, but how to harden and evolve the early framework implementation.

## Intentional current boundaries

A few important limits are still deliberate parts of the current design:

- the framework layer exists, but it is still experimental and library-first
- there is not yet a stable top-level runner CLI for end users
- the v1 runner is sequential and single-process, not a distributed or highly parallel worker system
- knowledge-base indexing is not implemented
- knowledge-base repair tooling is not implemented
- the server still uses a one-shot, reopen-on-change model rather than an incremental editable-document model

These are current product boundaries, not documentation gaps.

## Main roadmap items

### 1. Framework hardening and usability

The biggest remaining area is hardening the experimental framework into a more robust operator-facing system.
That includes work such as:

- refining prompts and task decomposition quality
- improving worker/orchestrator handoff quality and recovery behavior
- stabilizing user-facing run and inspection workflows
- expanding fixture coverage and end-to-end tests with controlled and real lower-layer interactions
- tuning model/provider configuration, pricing overrides, usage limits, and retry behavior
- improving operator visibility into task progress, run telemetry, and cost summaries

This work should continue to build on the explicit task system and lower-layer public interfaces rather than replacing them with ad hoc orchestration.

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

### 5. Longer-term framework expansion

Once the sequential framework loop has been hardened, possible later follow-ons include:

- richer human-in-the-loop review surfaces
- safe explicit re-initialization and project reset workflows
- parallel or graph-based execution only if the simple loop proves insufficient
- broader multi-project or fleet-style operational tooling

These should be justified by concrete workflow needs, not added preemptively.

## Practical priorities

If the project is advanced from the current state, the practical order should be:

1. keep `docs/` and `plans/framework*.md` aligned with the implemented four-layer stack
2. harden the experimental framework with fixture projects, controlled-model tests, and operator feedback
3. stabilize runner and inspection ergonomics before adding more orchestration complexity
4. add indexing, repair, or server follow-ons only when they unlock concrete workflows

## Summary

`aftk` now has a real four-layer stack:

- knowledge base
- informal bridge
- server / file worker
- experimental Python autoformalization framework

The lower three layers are the more mature foundation.
The main remaining work is to harden the fourth layer and selectively add follow-on capabilities such as indexing, repair, and server/interface evolution where they materially improve real workflows.
