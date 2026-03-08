# aftk

This repository is the rewrite worktree for `aftk`.

The Lean portion of the rewrite is now far enough along that the first three planned layers are implemented:

1. **Knowledge base**
2. **Informal bridge layer**
3. **Server / file-worker layer**

The planned TypeScript toolkit layer and AI-agent orchestration layer are **not implemented yet** in this worktree.

## What exists today

### Knowledge base

Implemented in `AFTK.KnowledgeBase`.

Current capabilities:

- canonical Markdown + JSON storage under a knowledge-base root
- strict node ids, metadata parsing, and canonical path layout
- node lifecycle operations: init, create, show, body update, metadata replace, rename, delete
- storage, metadata, node, and whole-root validation
- direct-scan text search and exact-tag search
- outgoing/incoming relationship queries
- CLI at `lake exe aftk knowledgebase ...`

### Informal layer

Implemented in `AFTK.Informal`.

Current capabilities:

- `informal[...]` elaboration backed by knowledge-base node ids
- explicit placeholder primitive for gradual formalization
- declaration-level tracking of successful informal references
- declaration and reference dependency projections
- compact and rich presentation rendering
- CLI at `lake exe aftk informal ...`

### Server / file-worker layer

Implemented in `AFTK.Server` and `AFTK.FileWorker`.

Current capabilities:

- standalone `aftk_server` hub and `aftk_file_worker` worker executables
- one worker per open Lean file
- JSON-RPC methods for hover, goals, term goals, infoview, tactic-state capture, and tactic execution
- reopen-on-change invalidation
- richer hover at `informal[...]` sites via the informal + knowledge-base layers

## Quick start

Build everything:

```text
lake build
```

Run the full test suite:

```text
lake test
```

### Knowledge-base CLI

Show help:

```text
lake exe aftk knowledgebase --help
```

Initialize a root:

```text
lake exe aftk knowledgebase init
```

Create a node:

```text
lake exe aftk knowledgebase create topology.open_cover --title "Open cover" --kind definition
```

Validate the root:

```text
lake exe aftk knowledgebase validate all
```

### Informal CLI

Show help:

```text
lake exe aftk informal --help
```

Query tracked declarations from a module:

```text
lake exe aftk informal decls --module AFTKTest.Informal.Fixtures.Basic
```

Render a knowledge-base node directly:

```text
lake exe aftk informal present group.basic.definition \
  --root tests/informal/knowledgebase-fixtures/basic-valid
```

### Server

Start the JSON-RPC hub:

```text
lake exe aftk_server
```

The hub speaks newline-delimited JSON-RPC over stdio and spawns `aftk_file_worker` processes as needed.

## Repository structure

Main implementation roots:

```text
AFTK/
  KnowledgeBase/
  Informal/
  Server/
  FileWorker/
AFTKTest/
  KnowledgeBase/
  Informal/
  Server/
docs/
plans/
tests/
```

## Documentation

Implementation-facing docs live under `docs/`.
Recommended entry points:

- `docs/README.md`
- `docs/architecture.md`
- `docs/knowledgebase/overview.md`
- `docs/informal/overview.md`
- `docs/server/overview.md`

More detailed references:

- knowledge base:
  - `docs/knowledgebase/storage.md`
  - `docs/knowledgebase/cli.md`
  - `docs/knowledgebase/library.md`
  - `docs/knowledgebase/testing.md`
- informal:
  - `docs/informal/library.md`
  - `docs/informal/cli.md`
  - `docs/informal/testing.md`
- server:
  - `docs/server/protocol.md`
  - `docs/server/testing.md`

Architectural and design documents remain under:

- `plan.md`
- `plans/knowledgebase*.md`
- `plans/informal*.md`
- `plans/server*.md`

## Current implementation boundaries

A few important things are still intentionally deferred:

- knowledge-base indexing
- knowledge-base repair tooling
- incremental editable-document server support
- the TypeScript toolkit layer
- the AI autoformalization agent layer

So the current rewrite is best understood as a solid Lean-core foundation for the larger architecture, not yet the complete planned stack.
