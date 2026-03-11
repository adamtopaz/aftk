# Implemented architecture

This document describes the current implementation state of the `aftk` codebase.
It is intentionally implementation-facing: it focuses on what is in code now, which files own which responsibilities, and where the current boundaries are.

## Current status

The architecture is organized into four layers:

1. Knowledge base
2. Informal
3. Server / file worker
4. Experimental AI autoformalization framework

Today, all four layers exist in the repository.
The first three Lean/toolkit layers are the more mature foundation.
The fourth layer is implemented in Python under `aftk/`, but it is still early and experimental.

For the project-level vision and remaining follow-on work, see `docs/roadmap.md`.
For the framework implementation plan that shaped the current Python layer, see `plans/framework.md` and `plans/framework/*.md`.

## Layer summary

| Layer | Current status | Main entrypoints | Main code roots |
| --- | --- | --- | --- |
| Knowledge base | Implemented | `lake exe aftk knowledgebase ...`, `import AFTK.KnowledgeBase` | `AFTK/KnowledgeBase*.lean`, `AFTK/KnowledgeBase/**` |
| Informal | Implemented | `lake exe aftk informal ...`, `import AFTK.Informal` | `AFTK/Informal*.lean`, `AFTK/Informal/**` |
| Server / file worker | Implemented | `lake exe aftk_server`, `lake exe aftk_file_worker <path>`, `import AFTK.Server`, `import AFTK.FileWorker` | `AFTK/Server*.lean`, `AFTK/Server/**`, `AFTK/FileWorker*.lean`, `AFTK/FileWorker/**` |
| Experimental framework | Implemented, experimental | `uv run aftk-inspect <project-root>`, `from aftk.runner import FrameworkRunner` | `aftk/**`, `aftk_client/**` |

## High-level dependency shape

The implemented stack is layered the way the broader project vision intends:

```text
AFTK.KnowledgeBase
        ↓
AFTK.Informal
        ↓
AFTK.Server / AFTK.FileWorker
        ↓
aftk_client
        ↓
aftk framework (.aftk state, agents, runner, inspection)
```

More concretely:

- `AFTK.KnowledgeBase` owns canonical natural-language storage and filesystem semantics.
- `AFTK.Informal` resolves `informal[...]` references through the knowledge base and tracks which Lean declarations use them.
- `AFTK.Server` and `AFTK.FileWorker` expose a long-running JSON-RPC service for Lean queries and tactic exploration, and reuse the informal layer for richer hover at `informal[...]` sites.
- `aftk_client` provides async Python wrappers over the implemented server/toolkit surface.
- `aftk/` adds deterministic project snapshots, a persistent task graph, worker coding tools, `pydantic-ai` agents, run telemetry, cost rollups, and operator inspection on top of the lower layers.

## Layer-to-component index

This section gives the shortest implementation map from layer to concrete components.
Use it as the top-level navigation guide into the codebase.

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
| Hub | `AFTK/Server/Hub.lean` | Sessions, spawning, forwarding, invalidation |
| Hub main | `AFTK/Server/Main.lean` | `aftk_server` executable bootstrap |
| Worker context | `AFTK/FileWorker/Context.lean` | One-shot Lean snapshot |
| Worker queries | `AFTK/FileWorker/Queries.lean` | Hover/goals/infoview queries |
| Worker tactic state | `AFTK/FileWorker/TacticState.lean` | Transient goal-state nodes and tactic execution |
| Worker informal integration | `AFTK/FileWorker/Informal.lean` | Rich `informal[...]` hover |
| Worker handlers | `AFTK/FileWorker/Handlers.lean` | Worker RPC method table |
| Worker main | `AFTK/FileWorker/Main.lean` | `aftk_file_worker` executable bootstrap |

### 4. Experimental AI autoformalization framework

Main docs:

- `docs/roadmap.md`
- `plans/framework.md`
- `plans/framework/tasks.md`
- `plans/framework/system.md`
- `plans/framework/coding_tools.md`

Main code components:

| Component | Code | Role |
| --- | --- | --- |
| Packaging bridge | `aftk/__init__.py`, `pyproject.toml` | Top-level Python package and transitional re-export of `aftk_client` |
| Toolkit client | `aftk_client/client.py`, `aftk_client/models.py`, `aftk_client/errors.py` | Async Python surface over the implemented server/toolkit APIs |
| Shared config and project snapshot | `aftk/config.py`, `aftk/project.py` | Discover project roots, entrypoints, sources, and persist `.aftk/project/snapshot.json` |
| Task system | `aftk/tasks/models.py`, `aftk/tasks/store.py`, `aftk/tasks/service.py` | Persistent task DAG, attempts, events, readiness, and restart recovery under `.aftk/tasks/` |
| Coding services | `aftk/coding/*` | Sandboxed project search, file reads/edits, command execution, and coding action logging |
| Run telemetry and costs | `aftk/storage/*` | Run records, LLM/tool call logs, usage summaries, pricing, and rollups under `.aftk/runs/` |
| Agents and tool wrappers | `aftk/agents/*` | Typed deps, structured outputs, role-scoped toolsets, and initializer/orchestrator/worker services |
| Runner and inspection | `aftk/runner.py`, `aftk/inspection.py`, `aftk/inspection_cli.py` | End-to-end runner loop plus operator-facing inspection reports and CLI |

## What is canonical, and where

### Canonical natural-language data

Canonical prose lives only in the knowledge base:

- Markdown body: `knowledgebase/nodes/**/*.md`
- metadata JSON: `knowledgebase/nodes/**/*.json`
- storage manifest: `knowledgebase/manifest.json`

The informal layer does **not** introduce a second prose store.

### Canonical framework control state

Within the experimental framework layer, the canonical project-control state is the task graph snapshot under:

- `.aftk/tasks/state.json`

The surrounding `.aftk/` files are supporting snapshots, immutable attempt records, and audit/telemetry artifacts around that explicit task state.

### Derived or transient data

The current implementation has four important kinds of non-canonical state:

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
4. **Framework runtime state** under `.aftk/`
   - `.aftk/project/` stores deterministic project snapshots
   - `.aftk/tasks/` stores the task graph, event log, and immutable attempts
   - `.aftk/runs/` stores run records, message logs, LLM/tool-call logs, usage/cost summaries, and coding-action logs

## Executables and user-facing commands

### Unified Lean CLI

The top-level Lean executable is:

```text
lake exe aftk <command> ...
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

### Python inspection CLI

The framework layer currently exposes an operator-facing inspection CLI:

```text
uv run aftk-inspect <project-root>
```

`aftk-inspect` renders text or JSON reports over `.aftk/` state.
The framework runner itself is currently library-first via `aftk.runner.FrameworkRunner` rather than a stable top-level user CLI.

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
- `aftk/__init__.py` — top-level Python package bridge
- `aftk/config.py` — shared framework config and path models
- `aftk/project.py` — deterministic project snapshot builder
- `aftk/runner.py` — initializer/orchestrator/worker runner loop
- `aftk/inspection.py` — operator-facing inspection service
- `aftk_client/client.py` — Python toolkit client
- `pyproject.toml` — Python packaging and `aftk-inspect` script registration
- `lakefile.lean` — Lake package config and executable definitions

## Testing structure

The repository currently has two main test tracks.

### Lean-layer tests

Run with:

```text
lake test
```

That driver runs the Lean test suites under `AFTKTest/`.
These tests use checked-in fixtures under `tests/`.

### Python client and framework tests

Run with:

```text
uv run python -m unittest discover -s tests/python -v
```

These tests cover:

- `aftk_client` integration and transport models
- framework config and project snapshot discovery
- persistent task-graph invariants and recovery
- coding-tool sandboxing and command execution
- agent model/dependency/tool wiring
- initializer/orchestrator/worker runner integration
- run telemetry, cost rollups, and inspection surfaces

They live under `tests/python/` and use fixtures under `tests/` and `tests/framework/`.

## Important current limitations

These are deliberate or current implementation boundaries:

- Knowledge-base **repair** and **indexing** are still incomplete follow-on work.
- The informal layer is read/query oriented; it does not mutate knowledge-base content.
- `informal[...]` uses an explicit unsound placeholder axiom for gradual formalization.
- The server uses a **one-shot file snapshot** model.
  It does not support in-memory versioned edits.
- File changes invalidate workers by file stamp and require reopen.
- The framework layer is early and experimental.
  It does not yet present a stable end-user runner CLI.
- The current framework runner is single-process and sequential.
  It intentionally relies on explicit persistent task state rather than distributed orchestration.
- Prompt quality, model selection, and operator UX for the framework are still evolving.

## Practical mental model

A good short mental model of the current codebase is:

- the **knowledge base** is the source of truth for prose,
- the **informal layer** turns knowledge-base node ids into Lean placeholders plus trackable declaration metadata,
- the **server layer** exposes Lean/editor-style queries over real files while enriching `informal[...]` hovers through the lower layers,
- `aftk_client` brings that lower-layer surface into Python,
- and the experimental `aftk/` framework persists `.aftk/` state and runs an initializer/orchestrator/worker loop on top of it.

If you keep those boundaries in mind, the current implementation becomes much easier to navigate.
