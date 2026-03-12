# aftk docs

This directory is the main home for repository documentation.
It now documents the Lean toolkit layers plus the Python client for `aftk_server`.
The previous experimental Python framework has been removed.

## Implemented components

The current repository includes four implementation areas:

1. **Knowledge base** — canonical Markdown + JSON storage, validation, search, relationships, and a CLI
2. **Informal** — `informal[...]` elaboration, declaration/reference tracking, dependency views, presentation, and a CLI
3. **Server / file-worker** — long-running JSON-RPC executables for Lean queries, tactic exploration, knowledge-base operations, and informal queries
4. **Python client** — async typed wrappers in `aftk/` for the public server protocol

## Reading order

If you want the shortest path to understanding the repository, read these first:

- `docs/architecture.md`
- `docs/roadmap.md`
- `docs/server/overview.md`
- `docs/knowledgebase/overview.md`
- `docs/informal/overview.md`

Then use the layer-specific guides for component-level detail.

## Knowledge base docs

- `docs/knowledgebase/overview.md` — layer scope, data model, and command surface
- `docs/knowledgebase/storage.md` — on-disk layout, node mapping, mutation semantics, and invariants
- `docs/knowledgebase/library.md` — component-by-component implementation guide with code pointers
- `docs/knowledgebase/cli.md` — command reference for `lake exe aftk knowledgebase ...`
- `docs/knowledgebase/testing.md` — test layout, fixtures, and coverage

## Informal docs

- `docs/informal/overview.md` — elaboration model, bridge semantics, and current behavior
- `docs/informal/library.md` — component-by-component implementation guide with code pointers
- `docs/informal/cli.md` — command reference for `lake exe aftk informal ...`
- `docs/informal/testing.md` — fixture layout, compile-fail tests, and CLI coverage

## Server / file-worker docs

- `docs/server/overview.md` — hub/worker architecture, executables, and lifecycle model
- `docs/server/library.md` — component-by-component implementation guide with code pointers
- `docs/server/protocol.md` — JSON-RPC method surface, result shapes, and error codes
- `docs/server/testing.md` — direct worker tests, hub tests, and end-to-end process coverage

## Planning docs

The remaining planning documents are the ones still relevant to the retained codebase:

- `plans/aftk-client.md` — design notes for the async Python client
- `plans/unified_server.md` — design notes for the unified server surface

## Project-level docs

Use the main repository docs this way:

- `docs/architecture.md` — the implemented architecture and current system boundaries
- `docs/roadmap.md` — the current direction for the Lean/toolkit foundation and future rebuilt automation work
- layer docs under `docs/**` — current behavior and code structure for each implemented area
