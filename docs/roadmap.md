# aftk roadmap

This document describes the project-level direction for `aftk` after the Python
framework/agent cleanup.
It complements `docs/architecture.md`, which focuses on the implementation that exists today.

## Project direction

`aftk` currently focuses on a Lean toolkit foundation plus a Python client for the
public server surface.
The implemented stack is:

1. **Knowledge base**
2. **Informal bridge layer**
3. **Server / file-worker layer**
4. **Python client**

The previous experimental Python agent/orchestration framework has been removed.
Future automation work is expected to restart from scratch on top of the retained
server/client boundary rather than evolve the deleted code in place.

## Core architectural commitments

The project continues to assume these core design choices:

- the **knowledge base** is the single source of truth for canonical prose and structured metadata
- the **informal layer** is the Lean-facing bridge to knowledge-base nodes
- the **server / file-worker layer** provides interactive Lean queries, tactic exploration, and direct knowledge-base/informal operations over JSON-RPC
- the **Python client** should stay a thin, typed wrapper over the public server protocol rather than duplicating server semantics
- any future rebuilt automation layer should sit on top of the existing public interfaces rather than reaching around them

In dependency order, the implemented stack is:

```text
AFTK.KnowledgeBase
        ↓
AFTK.Informal
        ↓
AFTK.Server / AFTK.FileWorker
        ↓
aftk
```

## Current implementation state

The repository already implements:

- **Knowledge base** — canonical Markdown + JSON storage, validation, search, relationships, and a CLI
- **Informal** — `informal[...]` elaboration, declaration-level tracking, dependency views, presentation, and a CLI
- **Server / file worker** — standalone JSON-RPC executables for Lean queries, richer hover, tactic exploration, knowledge-base operations, and informal queries
- **Python client** — async typed wrappers over the implemented server surface

So the immediate roadmap is about hardening and extending this foundation, not about
preserving the removed framework layer.

## Intentional current boundaries

A few important limits are deliberate parts of the current design:

- there is currently **no** retained Python agent/orchestration framework in the repository
- knowledge-base indexing is not implemented
- knowledge-base repair tooling is not implemented
- the server still uses a one-shot, reopen-on-change model rather than an incremental editable-document model
- the Python client is intentionally low-level and method-shaped; it is not a higher-level editor or workflow runtime

These are current product boundaries, not documentation gaps.

## Main roadmap items

### 1. Harden the server/client foundation

The most important near-term work is making the retained interface rock-solid.
That includes:

- keeping the JSON-RPC protocol stable and well documented
- expanding or refining typed client coverage when the server surface changes
- improving integration tests across Lean server behavior and Python client behavior
- making downstream dependency-style usage reliable for real Lean projects

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

### 4. Possible server evolution

The current server model is a deliberate one-shot, reopen-on-change design.
Possible follow-on work includes:

- richer editable-document support
- stronger diagnostics or progress integration
- request-cancellation improvements
- additional structured result surfaces where higher layers actually need them

This is follow-on work, not a prerequisite for the current foundation.

### 5. Design a new automation layer from scratch when ready

When automation work resumes, it should be treated as a fresh design problem rather than
an incremental continuation of the removed framework.
Useful prerequisites include:

- a stable server/client contract
- clear operator workflows the new system is meant to support
- updated design docs that reflect the retained codebase rather than the deleted framework

## Practical priorities

If the project is advanced from the current state, the practical order should be:

1. keep `docs/` aligned with the retained toolkit + client stack
2. harden the public server/client interface and its tests
3. add indexing, repair, or server follow-ons only when they unlock concrete workflows
4. design any future agent/orchestration system from scratch after the foundation is stable

## Summary

`aftk` now has a focused stack:

- knowledge base
- informal bridge
- server / file worker
- Python client

The main remaining work is to strengthen that foundation and use it as the basis for any
future rebuilt automation layer.
