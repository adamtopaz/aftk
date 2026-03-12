# AFTK

> [!WARNING]
> **Work in progress / highly experimental:** `aftk` is still at an early experimental stage.
> Things may break, interfaces may change, and behavior may shift at any time without much notice.
> Do not assume stability yet.

## About

AFTK is an AutoFormalization ToolKit for Lean 4.
It currently has four implemented layers, with the fourth still highly experimental:

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

### Experimental Python framework layer

Implemented in `aftk/` on top of `aftk_client/`.

Current capabilities:

- deterministic project snapshots and generated framework state under `.aftk/`
- a persistent task graph with attempts, events, and recovery on restart
- `pydantic-ai` initializer, orchestrator, and worker agents with typed dependencies and structured outputs
- worker-only coding tools for project search, file reads/edits, and validation commands such as `lake build`
- run telemetry, usage/cost rollups, and operator-facing inspection via `aftk-inspect`

This framework layer is real but still early: it is currently best understood as an experimental library and test surface rather than a stable end-user automation product.

## Quick start

Install the Python package and framework dependencies:

```text
uv sync
```

Build the Lean code:

```text
lake build
```

Run the Lean-layer tests:

```text
lake test
```

### Experimental framework quickstart

The framework now has a simple Hydra-backed CLI exposed as `autoformalize`.
A minimal project needs:

```text
my-project/
  lakefile.lean | lakefile.toml
  entrypoint.md
  sources/   # optional
```

Set the credentials required by your chosen `pydantic-ai` provider, then run from the project root with Hydra overrides for the three agent models:

```text
uv run autoformalize \
  project_root=. \
  models.initializer='openai:gpt-5-mini' \
  models.orchestrator='openai:gpt-5' \
  models.worker='openai:gpt-5-mini'
```

Useful overrides:

```text
uv run autoformalize \
  project_root=. \
  max_iterations=20 \
  state_dir=.aftk \
  output=text \
  models.initializer='openai:gpt-5-mini' \
  models.orchestrator='openai:gpt-5' \
  models.worker='openai:gpt-5-mini'
```

For more live visibility during a run, you can also raise the framework logging level or tune the trace settings:

```text
uv run autoformalize \
  project_root=. \
  logging.level=debug \
  logging.trace_model_events=full \
  logging.include_tool_payloads=full \
  models.initializer='openai:gpt-5-mini' \
  models.orchestrator='openai:gpt-5' \
  models.worker='openai:gpt-5-mini'
```

The CLI now emits framework-owned live progress logs by default, writes a session log to `.aftk/cli.log`, and appends structured runtime events to `.aftk/events.jsonl`.
It will create or resume `.aftk/` state and will start the toolkit server through `AsyncAftkClient` automatically unless you build your own runner integration.

If `aftk` is added as a Lake dependency in another Lean project, you can launch the same CLI from the dependent project's root with:

```text
lake run autoformalize \
  models.initializer='openai:gpt-5-mini' \
  models.orchestrator='openai:gpt-5' \
  models.worker='openai:gpt-5-mini'
```

That script resolves the Python package from the `aftk` dependency but runs it with the working directory set to the root of the current Lean/Lake project.

Inspect the resulting state with:

```text
uv run aftk-inspect .
```

For a fuller usage guide, see `docs/framework/overview.md`.

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

### Experimental framework inspection

After an experimental framework run has created `.aftk/`, inspect the persisted project/task/run state with:

```text
uv run aftk-inspect .
```

Use `uv run aftk-inspect --help` for JSON output and report-shaping options.

## Repository structure

Main implementation roots:

```text
AFTK/
  KnowledgeBase/
  Informal/
  Server/
  FileWorker/
aftk/
aftk_client/
AFTKTest/
docs/
plans/
tests/
```

## Documentation

Repository documentation lives under `docs/`.
Recommended entry points:

- `docs/README.md`
- `docs/architecture.md`
- `docs/roadmap.md`
- `docs/framework/overview.md`
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
- framework:
  - `docs/framework/overview.md`
  - `docs/framework/library.md`
  - `docs/framework/example-config.yaml`

Project-level vision and deferred work live in:

- `docs/roadmap.md` — project vision, long-term architecture, and main deferred work
- `plans/framework.md` and `plans/framework/*.md` — framework design and implementation sequencing notes

## Current implementation boundaries

A few important things are still intentionally deferred or unstable:

- knowledge-base indexing
- knowledge-base repair tooling
- incremental editable-document server support
- a stable end-user runner CLI and polished UX for the experimental framework layer
- further prompt/model refinement and operational hardening for the framework agents

So the current repository is best understood as a working four-layer stack, with the Lean/toolkit foundation more mature and the Python framework layer still experimental.
