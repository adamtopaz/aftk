# aftk documentation

This directory contains implementation-facing documentation for the current rewrite worktree.

## Knowledgebase layer

- `docs/knowledgebase/overview.md` — what the layer is, what is implemented, and how to get started
- `docs/knowledgebase/storage.md` — canonical on-disk layout, node mapping, and mutation semantics
- `docs/knowledgebase/cli.md` — CLI reference for `lake exe aftk knowledgebase ...`
- `docs/knowledgebase/library.md` — Lean library structure, core types, and API guide
- `docs/knowledgebase/testing.md` — how the test driver works and how to run/extend tests

## Relationship to `plans/`

The files under `plans/` are architectural and design documents.
The files under `docs/` describe the current implementation and intended usage.
