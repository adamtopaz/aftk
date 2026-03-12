# Implemented architecture

This document describes the current implementation state of the `aftk` codebase.
It is intentionally implementation-facing: it focuses on what is in code now,
which files own which responsibilities, and where the current boundaries are.

## Current status

The architecture is organized into four layers/components:

1. Knowledge base
2. Informal
3. Server / file worker
4. Python client

The first three are implemented in Lean.
The Python surface is now intentionally narrow: `aftk/` is the supported
Python API for the public `aftk_server` protocol.
The earlier experimental Python framework/agent layer has been removed.

For the project-level direction and deferred work, see `docs/roadmap.md`.

## Layer summary

| Layer | Current status | Main entrypoints | Main code roots |
| --- | --- | --- | --- |
| Knowledge base | Implemented | `lake exe aftk_cli knowledgebase ...`, `import AFTK.KnowledgeBase` | `AFTK/KnowledgeBase*.lean`, `AFTK/KnowledgeBase/**` |
| Informal | Implemented | `lake exe aftk_cli informal ...`, `import AFTK.Informal` | `AFTK/Informal*.lean`, `AFTK/Informal/**` |
| Server / file worker | Implemented | `lake exe aftk_server`, `lake exe aftk_file_worker <path>`, `import AFTK.Server`, `import AFTK.FileWorker` | `AFTK/Server*.lean`, `AFTK/Server/**`, `AFTK/FileWorker*.lean`, `AFTK/FileWorker/**` |
| Python client | Implemented | `from aftk import AsyncAftkClient` | `aftk/**`, `tests/python/**` |

## High-level dependency shape

The implemented stack is layered like this:

```text
AFTK.KnowledgeBase
        ↓
AFTK.Informal
        ↓
AFTK.Server / AFTK.FileWorker
        ↓
aftk
```

More concretely:

- `AFTK.KnowledgeBase` owns canonical natural-language storage and filesystem semantics.
- `AFTK.Informal` resolves `informal[...]` references through the knowledge base and tracks which Lean declarations use them.
- `AFTK.Server` and `AFTK.FileWorker` expose a long-running JSON-RPC service for Lean queries, tactic exploration, knowledge-base operations, and informal queries.
- `aftk` provides async Python wrappers over that public server surface.

## Layer-to-component index

### 1. Knowledge base layer

Main docs:

- `docs/knowledgebase/overview.md`
- `docs/knowledgebase/library.md`
- `docs/knowledgebase/storage.md`
- `docs/knowledgebase/cli.md`

Main code components:

| Component | Code | Role |
| --- | --- | --- |
| Public root | `AFTK/KnowledgeBase.lean` | Re-exports reusable knowledge-base modules |
| Types | `AFTK/KnowledgeBase/Types.lean` | Node ids, metadata, manifest, errors, JSON instances |
| Path layout | `AFTK/KnowledgeBase/PathLayout.lean` | Canonical root/path mapping |
| Serialization | `AFTK/KnowledgeBase/Serialization.lean` | Strict parsing and canonical rendering |
| Storage | `AFTK/KnowledgeBase/Storage.lean` | Real filesystem operations |
| Validation | `AFTK/KnowledgeBase/Validation.lean` | Structured validation reports |
| Search | `AFTK/KnowledgeBase/Search.lean` | Direct-scan search and relationship queries |
| Service | `AFTK/KnowledgeBase/Service.lean` | Shared execution helpers used by CLI and server |
| CLI | `AFTK/KnowledgeBase/Cli/*` | Parsing, dispatch, rendering, help |

### 2. Informal layer

Main docs:

- `docs/informal/overview.md`
- `docs/informal/library.md`
- `docs/informal/cli.md`

Main code components:

| Component | Code | Role |
| --- | --- | --- |
| Public root | `AFTK/Informal.lean` | Re-exports reusable informal modules |
| Syntax | `AFTK/Informal/Syntax.lean` | `informal[...]` syntax |
| Placeholder | `AFTK/Informal/Placeholder.lean` | Unsound placeholder primitive |
| Options | `AFTK/Informal/Options.lean` | `aftk.informal.root` option |
| References | `AFTK/Informal/References.lean` | Reference validation and KB-backed resolution |
| Tracking | `AFTK/Informal/Tracking.lean` | Persistent declaration→reference tracking |
| Dependencies | `AFTK/Informal/Dependencies.lean` | Derived dependency views |
| Presentation | `AFTK/Informal/Presentation.lean` | Compact/rich rendering |
| Elaborator | `AFTK/Informal/Elaborator.lean` | Actual term elaboration behavior |
| Service | `AFTK/Informal/Service.lean` | Shared execution helpers used by CLI and server |
| CLI | `AFTK/Informal/Cli/*` | Parsing, environment import, rendering |

### 3. Server / file-worker layer

Main docs:

- `docs/server/overview.md`
- `docs/server/library.md`
- `docs/server/protocol.md`

Main code components:

| Component | Code | Role |
| --- | --- | --- |
| Hub public root | `AFTK/Server.lean` | Re-exports hub-side modules |
| Worker public root | `AFTK/FileWorker.lean` | Re-exports worker-side modules |
| Protocol | `AFTK/Server/Protocol.lean` | Shared JSON-RPC types and error helpers |
| Transport | `AFTK/Server/Transport.lean` | StdIO transport and child-process helpers |
| Hub | `AFTK/Server/Hub.lean` | Sessions, spawning, forwarding, invalidation, direct KB/informal handlers |
| Hub main | `AFTK/Server/Main.lean` | `aftk_server` executable bootstrap |
| Worker context | `AFTK/FileWorker/Context.lean` | One-shot Lean snapshot |
| Worker queries | `AFTK/FileWorker/Queries.lean` | Hover/goals/infoview queries |
| Worker tactic state | `AFTK/FileWorker/TacticState.lean` | Transient goal-state nodes and tactic execution |
| Worker informal integration | `AFTK/FileWorker/Informal.lean` | Rich `informal[...]` hover |
| Worker handlers | `AFTK/FileWorker/Handlers.lean` | Worker RPC method table |
| Worker main | `AFTK/FileWorker/Main.lean` | `aftk_file_worker` executable bootstrap |

### 4. Python client

Main code components:

| Component | Code | Role |
| --- | --- | --- |
| Public exports | `aftk/__init__.py` | Public API re-exports for the Python client |
| High-level client | `aftk/client.py` | Async request wrappers, project-root handling, convenience methods |
| Wire models | `aftk/models.py` | Pydantic request/result models for server methods |
| JSON-RPC envelopes | `aftk/jsonrpc.py` | Request/response envelope models |
| Errors | `aftk/errors.py` | Typed exception hierarchy and JSON-RPC error mapping |
| Transport | `aftk/transport.py` | Async subprocess transport and request multiplexing |

## What is canonical, and where

### Canonical natural-language data

Canonical prose lives only in the knowledge base:

- Markdown body: `knowledgebase/nodes/**/*.md`
- metadata JSON: `knowledgebase/nodes/**/*.json`
- storage manifest: `knowledgebase/manifest.json`

The informal layer does **not** introduce a second prose store.

### Derived or transient data

The current implementation has three important kinds of non-canonical state:

1. **Knowledge-base internal directories** under `knowledgebase/.aftk/`
   - reserved for internal/derived data
   - currently created by `init`
   - indexing and repair logic are still deferred
2. **Informal tracking state** inside Lean environments
   - declaration → referenced-node associations
   - imported and merged by a `SimplePersistentEnvExtension`
3. **Worker-local tactic state** in the server layer
   - opaque ids like `node-0`, `node-1`, ...
   - session-local and non-persistent
   - invalidated by worker restart or file reopen

## Executables and user-facing commands

### Unified Lean CLI

The top-level Lean executable is:

```text
lake exe aftk_cli <command> ...
```

It currently dispatches to:

- `knowledgebase`
- `informal`

The dispatch logic lives in `Main.lean`.

### Standalone server executables

The server layer is exposed separately:

```text
lake exe aftk_server
lake exe aftk_file_worker <path>
```

`aftk_server` is the public JSON-RPC hub.
`aftk_file_worker` is the internal per-file worker executable spawned by the hub.

### Python API

There is no longer a repository-owned Python automation CLI.
The supported Python interface is the client library:

```python
from aftk import AsyncAftkClient
```

## Top-level code roots

These are the highest-level code files to read first:

- `AFTK.lean` — umbrella Lean import
- `Main.lean` — top-level Lean CLI dispatch to `knowledgebase` and `informal`
- `AFTK/KnowledgeBase.lean` — knowledge-base public root
- `AFTK/Informal.lean` — informal public root
- `AFTK/Server.lean` — server public root
- `AFTK/FileWorker.lean` — file-worker public root
- `AFTK/Server/Main.lean` — hub executable main
- `AFTK/FileWorker/Main.lean` — worker executable main
- `aftk/__init__.py` — Python client public exports
- `aftk/client.py` — Python client
- `aftk/models.py` — Python wire models
- `aftk/transport.py` — Python subprocess transport
- `pyproject.toml` — Python packaging
- `lakefile.lean` — Lake package config and executable definitions

## Testing structure

The repository currently has two main test tracks.

### Lean-layer tests

Run with:

```text
lake exe aftk_test
```

The server-focused Lean suite can also be run directly with:

```text
lake exe aftk_server_test
```

These tests use checked-in fixtures under `tests/`.

### Python client tests

Run with:

```text
uv run python -m unittest discover -s tests/python -v
```

These tests cover:

- `aftk` integration against a real `aftk_server` subprocess
- request/result model validation and alias behavior
- project-root detection and validation
- JSON-RPC/domain error mapping

## Important current limitations

These are deliberate or current implementation boundaries:

- Knowledge-base repair and indexing are still incomplete follow-on work.
- The informal layer is read/query oriented; it does not mutate knowledge-base content.
- `informal[...]` uses an explicit unsound placeholder axiom for gradual formalization.
- The server uses a one-shot file snapshot model.
  It does not support in-memory versioned edits.
- File changes invalidate workers by file stamp and require reopen.
- There is intentionally no retained Python agent/orchestration layer in the current tree.
  Future automation work will restart from the server/client foundation.

## Practical mental model

A good short mental model of the current codebase is:

- the **knowledge base** is the source of truth for prose,
- the **informal layer** turns knowledge-base node ids into Lean placeholders plus trackable declaration metadata,
- the **server layer** exposes Lean/editor-style queries over real files while reusing the lower layers,
- and `aftk` brings that public server surface into Python.

If you keep those boundaries in mind, the current implementation becomes much easier to navigate.
