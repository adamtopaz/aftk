# AFTK

> [!WARNING]
> **Work in progress / highly experimental:** `aftk` is still at an early experimental stage.
> Things may break, interfaces may change, and behavior may shift at any time without much notice.
> Do not assume stability yet.

## About

AFTK is an AutoFormalization ToolKit for Lean4.
It consists of four layers:

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

### Toolkit / pi integration layer

Implemented in `src/toolkit/` and `src/hosts/pi/`.

Current capabilities:

- Node-compatible runtime context with project-root discovery and subprocess helpers
- managed TypeScript client for `aftk_server`
- CLI-backed TypeScript clients for `aftk knowledgebase ...` and `aftk informal ...`
- Lean/server-backed `aftk_*` tools
- knowledge-base `knowledgebase_*` tools
- informal `informal_*` tools
- aggregate toolkit assembly and thin pi integration helpers
- Lake setup script `lake run aftk_setup` for project-local pi extension/prompt installation
- dedicated TypeScript-side tests under `tests/toolkit/`

## Quick start

Build the Lean code:

```text
lake build
```

Run the Lean-layer tests:

```text
lake test
```

Run the toolkit typecheck:

```text
npm run check
```

Run the toolkit tests:

```text
npm run test:toolkit
```

Run everything together:

```text
npm run test:all
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

### Toolkit setup for pi

Install or refresh the local pi shims and appended prompt for the current Lake workspace:

```text
lake run aftk_setup
```

This installs:

- `.pi/extensions/aftk-toolkit.ts`
- `.pi/extensions/aftk-logging.ts`
- `.pi/APPEND_SYSTEM.md`

The logging extension keeps pi session logs under `.aftk/logs/` and per-run cost summaries under `.aftk/cost/`.

To edit the generated appended system prompt, update `src/hosts/pi/APPEND_SYSTEM.template.md` and rerun the setup command.

If pi is already running after setup, use `/reload`.

### Noninteractive stigmergic loop

Run fresh noninteractive pi passes in a loop until the agent marks the whole task as done:

```text
lake run aftk_autoformalize_loop Formalize the next meaningful frontier from entrypoint.md
```

This script never uses `--continue`.
Each iteration runs `pi --print --no-session`, expects work to proceed stigmergically from durable repo state, and stops only when the final marker is `AFTK_LOOP_DONE`.
The loop honors `AFTK_PI_COMMAND` when set and otherwise probes available `pi` binaries, preferring the newest runnable version.
See `docs/aftk_autoformalize_loop.md`.

## Repository structure

Main implementation roots:

```text
AFTK/
  KnowledgeBase/
  Informal/
  Server/
  FileWorker/
AFTKTest/
src/
  toolkit/
  hosts/pi/
docs/
tests/
  toolkit/
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
- `docs/toolkit/overview.md`

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
- toolkit:
  - `docs/toolkit/library.md`
  - `docs/toolkit/testing.md`
  - `docs/aftk_setup.md`
  - `docs/aftk_autoformalize_loop.md`

Project-level vision and deferred work live in:

- `docs/roadmap.md` — project vision, long-term architecture, and main deferred work

## Current implementation boundaries

A few important things are still intentionally deferred:

- knowledge-base indexing
- knowledge-base repair tooling
- incremental editable-document server support
- broader toolkit mutation/admin coverage for the knowledge-base and informal CLIs
- the AI autoformalization agent layer

So the current repository is best understood as a solid Lean-core-plus-toolkit foundation for the larger architecture, not yet the complete planned stack.
