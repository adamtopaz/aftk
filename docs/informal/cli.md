# Informal CLI reference

The public command is:

```text
lake exe aftk informal ...
```

This CLI is implemented in `AFTK/Informal/Cli/*` and dispatched from the top-level `aftk` executable.

## Help system

Help is available at:

```text
lake exe aftk --help
lake exe aftk informal --help
lake exe aftk informal <command> --help
```

The informal CLI accepts both `--help` and `-h` in help detection.

## Two command classes

The implemented commands fall into two groups.

### 1. Environment-backed tracking/dependency queries

These commands inspect tracking state stored in imported Lean modules:

- `status`
- `decls`
- `decl`
- `refs`
- `ref`
- `deps`

All of these require at least one:

```text
--module <Module.Name>
```

### 2. Direct knowledge-base presentation

This command resolves a node directly through the knowledge base:

- `present`

`present` does **not** require `--module`.

## Global options

All commands accept:

- `--module <Module.Name>` — repeatable
- `--root <path>`
- `--format text|json`
- `--help`

Important notes:

- `--module` is meaningful only for environment-backed queries
- `--root` matters primarily for `present`
- JSON success output is command-shaped rather than using the knowledge-base CLI envelope

## Exit codes

The informal CLI reuses `KnowledgeBaseError` exit codes:

- `0` — success
- `1` — generic operational/query failure
- `2` — usage error
- `3` — targeted not-found / not-tracked error
- `4` — validation-style failure, such as malformed knowledge-base data during `present`
- `5` — reserved conflict code, though current informal commands are read-oriented

## Commands

### `status`

Show high-level counts:

```text
lake exe aftk informal status --module AFTKTest.Informal.Fixtures.Basic
```

Current text output reports:

- tracked declarations
- tracked references
- declarations with multiple references

### `decls`

List tracked declarations:

```text
lake exe aftk informal decls --module AFTKTest.Informal.Fixtures.Basic
lake exe aftk informal decls --module AFTKTest.Informal.Fixtures.Basic --prefix AFTKTest.Informal.Fixtures.Basic
lake exe aftk informal decls --module AFTKTest.Informal.Fixtures.Basic --ref group.basic.definition
```

Options:

- `--prefix <Decl.Name>`
- `--ref <NodeId>`

Rows are declaration-level and use deduplicated reference sets.

### `decl <Decl.Name>`

Show one tracked declaration:

```text
lake exe aftk informal decl \
  AFTKTest.Informal.Fixtures.Basic.multiRef \
  --module AFTKTest.Informal.Fixtures.Basic
```

This returns the declaration, its reference count, and its referenced node ids.

### `refs`

List tracked references:

```text
lake exe aftk informal refs --module AFTKTest.Informal.Fixtures.Basic
lake exe aftk informal refs --module AFTKTest.Informal.Fixtures.Basic --prefix group.basic
```

Option:

- `--prefix <NodeIdPrefix>`

Rows group by reference and list the declarations that reference each node id.

### `ref <NodeId>`

Show one tracked reference:

```text
lake exe aftk informal ref group.basic.definition --module AFTKTest.Informal.Fixtures.Basic
```

This returns the node id, declaration count, and declarations that reference it.

### `deps`

Show derived dependency views:

```text
lake exe aftk informal deps --module AFTKTest.Informal.Fixtures.Imports.Top
lake exe aftk informal deps --module AFTKTest.Informal.Fixtures.Imports.Top --by decl
lake exe aftk informal deps --module AFTKTest.Informal.Fixtures.Imports.Top --by ref
lake exe aftk informal deps --module AFTKTest.Informal.Fixtures.Imports.Top --by ref --only-leaves
```

Options:

- `--by decl|ref`
- `--only-leaves`

Semantics:

- `decl` mode reports tracked declaration dependencies
- `ref` mode reports projected reference dependencies
- `--only-leaves` filters displayed rows to empty-dependency leaves

The output still includes the leaf summary section.

### `present <NodeId>`

Render direct knowledge-base-backed presentation:

```text
lake exe aftk informal present group.basic.definition --root tests/informal/knowledgebase-fixtures/basic-valid
lake exe aftk informal present analysis.uniform_continuity \
  --root tests/informal/knowledgebase-fixtures/long-body \
  --mode rich \
  --body preview
lake exe aftk informal present group.basic.definition \
  --root tests/informal/knowledgebase-fixtures/basic-valid \
  --mode compact \
  --format json
```

Options:

- `--mode compact|rich`
- `--body none|preview|full`
- `--root <path>`

Behavior:

- `compact` renders the summary only
- `rich` renders tags, authors, relationships, Lean refs, and body according to the chosen body mode
- `preview` is the default body mode for rich rendering

## Text output

Text output is designed for quick inspection.

Examples of the current style:

- `decls` and `refs` print a header line plus one bullet per row
- `decl` and `ref` print a small focused block
- `deps` prints rows plus a separate `Leaves (...)` section
- `present` reuses the presentation renderer from `AFTK.Informal.Presentation`

## JSON output

Unlike the knowledge-base CLI, informal success JSON is currently command-shaped rather than wrapped in a common `ok/result` envelope.

Example success shape for `decls`:

```json
{
  "modules": ["AFTKTest.Informal.Fixtures.Basic"],
  "data": {
    "entries": [ ... ]
  },
  "command": "decls"
}
```

Example success shape for `present --mode compact`:

```json
{
  "command": "present",
  "target": "group.basic.definition",
  "mode": "compact",
  "data": {
    "summary": { ... }
  }
}
```

Failures in JSON mode include a structured error object and `ok: false`.

## Common failure cases

### Missing `--module`

Environment-backed commands fail with a usage error if no module is provided:

```text
missing required option '--module <Module.Name>'
```

### Invalid dependency mode

```text
lake exe aftk informal deps --module Foo --by bogus
```

fails with a usage error describing the accepted `decl|ref` values.

### Not tracked

Targeted `decl` and `ref` queries return exit code `3` when the requested declaration or node id is not tracked in the imported environment.

### Invalid or malformed node presentation

`present` can fail because:

- the node id is syntactically invalid
- the root is missing or uninitialized
- the node does not exist
- the node metadata is malformed

The last case is especially important because `present` uses the knowledge-base layer's strict parsing and validation behavior.

## Practical examples

List the declarations that reference one node:

```text
lake exe aftk informal decls \
  --module AFTKTest.Informal.Fixtures.Basic \
  --ref group.basic.definition
```

Show projected reference dependencies:

```text
lake exe aftk informal deps \
  --module AFTKTest.Informal.Fixtures.Imports.Top \
  --by ref
```

Render a long-body node in preview mode:

```text
lake exe aftk informal present analysis.uniform_continuity \
  --root tests/informal/knowledgebase-fixtures/long-body \
  --mode rich \
  --body preview
```
