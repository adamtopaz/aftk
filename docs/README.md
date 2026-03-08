# aftk implementation docs

This directory documents the parts of the rewrite worktree that are currently implemented.

## Implemented layers

The Lean portion of the rewrite currently includes three working layers:

1. **Knowledge base** — canonical Markdown + JSON storage, validation, search, relationships, and a CLI
2. **Informal** — `informal[...]` elaboration, declaration-level tracking, dependency views, presentation, and a CLI
3. **Server / file worker** — standalone JSON-RPC executables for Lean queries, tactic exploration, and richer informal hover

The planned TypeScript toolkit and AI-agent orchestration layers are **not implemented yet** in this worktree.

## Reading order

If you want the shortest path to understanding the system, read these first:

- `docs/architecture.md`
- `docs/knowledgebase/overview.md`
- `docs/informal/overview.md`
- `docs/server/overview.md`

## Knowledge base docs

- `docs/knowledgebase/overview.md` — current scope, data model, and command surface
- `docs/knowledgebase/storage.md` — on-disk layout, node mapping, mutation semantics, and invariants
- `docs/knowledgebase/cli.md` — command reference for `lake exe aftk knowledgebase ...`
- `docs/knowledgebase/library.md` — Lean module guide and key public APIs
- `docs/knowledgebase/testing.md` — test layout, fixtures, and coverage

## Informal docs

- `docs/informal/overview.md` — elaboration model, bridge semantics, and current behavior
- `docs/informal/library.md` — syntax, placeholder, tracking, dependency, and presentation APIs
- `docs/informal/cli.md` — command reference for `lake exe aftk informal ...`
- `docs/informal/testing.md` — fixture layout, compile-fail tests, and CLI coverage

## Server / file-worker docs

- `docs/server/overview.md` — hub/worker architecture, executables, and lifecycle model
- `docs/server/protocol.md` — JSON-RPC method surface, result shapes, and error codes
- `docs/server/testing.md` — direct worker tests, hub tests, and end-to-end process coverage

## Relationship to `plan.md` and `plans/`

The files under `plan.md` and `plans/` are architectural and design-oriented.
The files under `docs/` describe the implementation that is actually present in this rewrite worktree today.
