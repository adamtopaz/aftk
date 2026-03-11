# AFTK

> [!WARNING]
> **Work in progress / highly experimental:** `aftk` is still at an early experimental stage.
> Things may break, interfaces may change, and behavior may shift at any time without much notice.
> Do not assume stability yet.

## About

AFTK is an AutoFormalization ToolKit for Lean 4.
It currently has three implemented layers:

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
- direct JSON-RPC methods for knowledge-base operations and informal-layer queries/presentation
- reopen-on-change invalidation
- richer hover at `informal[...]` sites via the informal + knowledge-base layers
- async Python client wrappers in `aftk_client/` for the public server surface

Higher-level automation and agent orchestration are not implemented in this branch.

## Quick start

Build the Lean code:

```text
lake build
```

Run the Lean-layer tests:

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
docs/
tests/
```

## Documentation

Repository documentation lives under `docs/`.
Recommended entry points:

- `docs/README.md`
- `docs/architecture.md`
- `docs/roadmap.md`
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
  - `docs/server/library.md`
  - `docs/server/protocol.md`
  - `docs/server/testing.md`

Project-level vision and deferred work live in:

- `docs/roadmap.md` — project vision, long-term architecture, and main deferred work

## Current implementation boundaries

A few important things are still intentionally deferred:

- knowledge-base indexing
- knowledge-base repair tooling
- incremental editable-document server support
- the AI autoformalization agent layer

So the current repository is best understood as a Lean-core foundation for the larger architecture, not yet the complete planned stack.
