# aftk docs

This directory is the main home for repository documentation.
Most files here document the implementation that exists today: modules, executables, responsibilities, boundaries, and tested behavior.
`docs/roadmap.md` is the project-level roadmap document for overall vision and deferred work.
For the experimental Python framework layer, the design docs in `plans/framework.md` and `plans/framework/*.md` are also useful references.

## Implemented layers

The current repository includes four working layers, though the fourth is still experimental:

1. **Knowledge base** — canonical Markdown + JSON storage, validation, search, relationships, and a CLI
2. **Informal** — `informal[...]` elaboration, declaration-level tracking, dependency views, presentation, and a CLI
3. **Server / file worker** — standalone JSON-RPC executables for Lean queries, tactic exploration, and richer informal hover
4. **Python framework** — persistent `.aftk/` project state, `pydantic-ai` initializer/orchestrator/worker runtime, worker coding tools, usage/cost rollups, and `aftk-inspect`

The framework layer is implemented but still evolving.
Use `docs/architecture.md`, `docs/roadmap.md`, and `plans/framework.md` together when you need the current implementation plus the intended direction.

## Reading order

If you want the shortest path to understanding the repository, read these first:

- `docs/architecture.md`
- `docs/roadmap.md`
- `docs/framework/overview.md`
- `plans/framework.md`
- `docs/knowledgebase/overview.md`
- `docs/informal/overview.md`
- `docs/server/overview.md`

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

## Framework docs

- `docs/framework/overview.md` — project requirements, Python runner usage, `.aftk/` state layout, and inspection workflow
- `docs/framework/library.md` — module-by-module guide to the Python framework APIs and main services
- `docs/framework/example-config.yaml` — example Hydra config for `autoformalize`

## Project-level docs

Use the main repository docs this way:

- `docs/architecture.md` — the implemented architecture and current system boundaries
- `docs/roadmap.md` — the project-level vision, long-term direction, and intentionally deferred work
- `plans/framework.md` and `plans/framework/*.md` — framework design intent, implementation phases, and detailed subsystem plans
- layer docs under `docs/**` — current behavior and code structure for each implemented area
