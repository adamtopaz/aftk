# Knowledgebase storage

This document describes the current implemented storage format.

## Root discovery

By default, the CLI resolves the root as:

```text
knowledgebase/
```

relative to the current working directory.

You can override it with:

```text
--root <path>
```

The CLI does not perform upward directory search.
All commands except `init` require the resolved root to already be initialized.

## Root layout

```text
knowledgebase/
  manifest.json
  nodes/
  .aftk/
    index/
    cache/
    tmp/
```

### `manifest.json`

The manifest is small and strict:

```json
{
  "schemaVersion": 1,
  "kind": "aftk-knowledge-base",
  "nodesDir": "nodes",
  "internalDir": ".aftk"
}
```

Unknown fields are rejected.

## Node ID mapping

Node IDs use lowercase dotted segments.

Examples:

- `topology.open_cover`
- `group.basic.definition`
- `analysis.uniform_continuity`

Rules:

- nonempty
- dot-separated segments
- no empty segments
- no whitespace
- no `/` or `\`
- each segment starts with a lowercase ASCII letter
- remaining segment characters are lowercase ASCII letters, digits, or `_`

Mapping rule:

- split on `.`
- directories are all segments except the last
- basename is the last segment

So:

- `group.basic.definition` -> `group/basic/definition`

## Node file pairing

For a node stem `<stem>`, the canonical files are:

- `<stem>.md`
- `<stem>.json`

Both must exist together for a valid stored node.

## Markdown behavior

Markdown is stored as plain UTF-8 text.

Writers:

- normalize line endings to `\n`
- write a trailing newline

Readers:

- normalize line endings to `\n`

## Metadata behavior

Metadata is strict JSON.

Implemented properties:

- required fields are enforced
- unsupported schema versions are rejected
- unknown fields are rejected
- deterministic field ordering is used when writing
- optional/default fields are omitted when absent

### Field order

Current canonical writer order:

1. `schemaVersion`
2. `id`
3. `title`
4. `kind`
5. `status`
6. `summary`
7. `tags`
8. `authors`
9. `createdAt`
10. `updatedAt`
11. `relationships`
12. `leanRefs`

## Mutation semantics

### Create

`create` writes both files.
Defaults:

- empty body allowed
- `kind = note`
- `status = draft`
- `createdAt` and `updatedAt` set to the creation timestamp

### Body replacement

`body set` rewrites the Markdown body and refreshes `updatedAt`.

### Metadata replacement

`metadata replace` rewrites the full metadata object and refreshes `updatedAt`.
It must preserve the target node ID.

### Rename

`rename` updates:

- the metadata ID
- the canonical Markdown path
- the canonical metadata path
- `updatedAt`

### Delete

`delete` removes both canonical node files.

## Validation-relevant invariants

The implementation checks these storage-level invariants:

- manifest exists and parses
- manifest schema is supported
- nodes directory exists
- path-derived node ID matches metadata ID
- no orphan `.md` file without `.json`
- no orphan `.json` file without `.md`
- duplicate node IDs are rejected during whole-root validation
- missing relationship targets are reported during whole-root validation

## Direct editing

The storage format is intentionally human-editable.
However, if you edit files by hand, you should run:

```text
lake exe aftk knowledgebase validate all
```

afterward.
