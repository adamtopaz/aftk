# AFTK

> [!WARNING]
> AFTK is still experimental. The Lean toolkit layers and the Python client are usable,
> but interfaces may still change.

## About

AFTK is an AutoFormalization ToolKit for Lean 4.
After the current cleanup, the repository contains:

1. **Knowledge base** — canonical Markdown + JSON storage, validation, search, relationships, and a Lean CLI
2. **Informal layer** — `informal[...]` elaboration, declaration/reference tracking, dependency views, presentation, and a Lean CLI
3. **Server / file-worker layer** — JSON-RPC executables for Lean queries, tactic exploration, knowledge-base operations, and informal queries
4. **Python client** — async typed wrappers in `aftk/` for the public `aftk_server` surface

The previous experimental Python agent/framework layer has been removed.
Future agent work will be rebuilt separately on top of the server/client boundary.

## Quick start

Install the Python dependencies:

```text
uv sync
```

Build the Lean code:

```text
lake build
```

Run the Lean tests:

```text
lake exe aftk_test
```

Run the Python client tests:

```text
uv run python -m unittest discover -s tests/python -v
```

## Lean CLIs

### Knowledge base

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

### Informal

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

## Server

Start the JSON-RPC hub:

```text
lake exe aftk_server
```

The hub speaks newline-delimited JSON-RPC over stdio and spawns `aftk_file_worker`
processes as needed.

Run the Lean server-specific tests with:

```text
lake exe aftk_server_test
```

## Python client

The supported Python API lives in `aftk/`.
Because the repository is still pre-release and experimental, we do not preserve old Python package names.
Import the client from `aftk` directly.

Example:

```python
from pathlib import Path

from aftk import AsyncAftkClient


async def main() -> None:
    project_root = Path(".").resolve()
    async with AsyncAftkClient(project_root=project_root) as client:
        opened = await client.open("tests/server/fixtures/lean/Semantics.lean")
        hover = await client.get_hover(opened.path, 10, 26)
        print(hover.text if hover is not None else "no hover")
```

The client also exposes typed wrappers for the server's knowledge-base and informal
method families.
See `aftk/client.py`, `aftk/models.py`, and `tests/python/`.

## Repository structure

Main implementation roots:

```text
AFTK/
  KnowledgeBase/
  Informal/
  Server/
  FileWorker/
aftk/          # Python client package
AFTKTest/
docs/
plans/
tests/
```

## Documentation

Recommended entry points:

- `docs/README.md`
- `docs/architecture.md`
- `docs/roadmap.md`
- `docs/knowledgebase/overview.md`
- `docs/informal/overview.md`
- `docs/server/overview.md`

Useful detail references:

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
- plans:
  - `plans/aftk-client.md`
  - `plans/unified_server.md`

## Current boundaries

A few important things are still intentionally deferred or limited:

- knowledge-base indexing
- knowledge-base repair tooling
- incremental editable-document server support
- any rebuilt agent/orchestration layer beyond the current client/server foundation

So the repository is now best understood as a Lean toolkit stack plus a focused Python
client for the public server surface.
