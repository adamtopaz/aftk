# aftk implementation docs

This directory documents the parts of the rewrite worktree that are currently implemented.
The emphasis is on implementation reality: modules, executables, package entrypoints, responsibilities, boundaries, and tested behavior.

## Implemented layers

The rewrite currently includes four working layers:

1. **Knowledge base** — canonical Markdown + JSON storage, validation, search, relationships, and a CLI
2. **Informal** — `informal[...]` elaboration, declaration-level tracking, dependency views, presentation, and a CLI
3. **Server / file worker** — standalone JSON-RPC executables for Lean queries, tactic exploration, and richer informal hover
4. **Toolkit** — a TypeScript runtime, managed server client, CLI-backed knowledge-base/informal clients, tool families, pi adapters, and a Lake setup script

The planned AI autoformalization agent layer is **not implemented yet** in this worktree.
Its remaining high-level status is described in `docs/architecture.md`.

## Reading order

If you want the shortest path to understanding the implementation, read these first:

- `docs/architecture.md`
- `docs/knowledgebase/overview.md`
- `docs/informal/overview.md`
- `docs/server/overview.md`
- `docs/toolkit/overview.md`

Then use the layer-specific implementation guides for component-level details.

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

## Toolkit docs

- `docs/toolkit/overview.md` — layer scope, runtime model, tool families, result contract, and pi integration surface
- `docs/toolkit/library.md` — component-by-component implementation guide with code pointers
- `docs/toolkit/testing.md` — package scripts, test layout, fixtures, and current TypeScript-side coverage

## Setup / integration docs

- `docs/aftk_setup.md` — `lake run aftk_setup`, generated `.pi/` files, discovery model, and overwrite policy

## Relationship to `plan.md` and `plans/`

The files under `plan.md` and `plans/` are architectural and design-oriented.
The files under `docs/` describe the implementation that is actually present in this rewrite worktree today.
