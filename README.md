# aftk

This repository is the rewrite worktree for `aftk`.

## Current implemented layer

The knowledgebase layer is now implemented in Lean with:

- canonical Markdown + JSON storage under `knowledgebase/`
- a CLI at `lake exe aftk knowledgebase ...`
- validation, search, and relationship traversal
- a dedicated `AFTKTest/` test tree and a Lake test driver, so tests run with `lake test`

## Common commands

Build:

```text
lake build
```

Run the knowledgebase CLI:

```text
lake exe aftk knowledgebase status
```

Get CLI help:

```text
lake exe aftk --help
lake exe aftk knowledgebase --help
lake exe aftk knowledgebase create --help
```

Run tests:

```text
lake test
```

## Documentation

Implementation docs:

- `docs/README.md`
- `docs/knowledgebase/overview.md`
- `docs/knowledgebase/storage.md`
- `docs/knowledgebase/cli.md`
- `docs/knowledgebase/library.md`
- `docs/knowledgebase/testing.md`

Architectural and planning docs:

- `plan.md`
- `plans/knowledgebase.md`
- `plans/knowledgebase/*.md`
