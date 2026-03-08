# Knowledge-base storage

This document describes the canonical on-disk format implemented by `AFTK.KnowledgeBase`.

## Root resolution

`AFTK.KnowledgeBase.PathLayout.resolveRootPath` and the CLI use this policy:

- if `--root <path>` is provided, use that path
- otherwise use `knowledgebase/` relative to the current working directory
- relative paths are resolved against the current working directory
- no upward search is performed

So the root is always explicit and local.

## Root layout

The default manifest and directory structure are:

```text
knowledgebase/
  manifest.json
  nodes/
  .aftk/
    index/
    cache/
    tmp/
```

### Canonical files

Canonical source-of-truth files are:

- `manifest.json`
- `nodes/**/*.md`
- `nodes/**/*.json`

### Reserved internal area

The `.aftk/` directory is internal/reserved space.
It is created by `init` and surfaced by `status`, but indexing and repair logic are not yet implemented.

## Manifest format

The manifest is small and strict:

```json
{
  "schemaVersion": 1,
  "kind": "aftk-knowledge-base",
  "nodesDir": "nodes",
  "internalDir": ".aftk"
}
```

Current manifest rules:

- `schemaVersion` must be `1`
- `kind` must be `aftk-knowledge-base`
- unknown fields are rejected
- the current writer emits deterministic field order

## Node id to path mapping

`AFTK.KnowledgeBase.PathLayout.nodeIdToRelativeStem` implements the canonical mapping.

For a node id:

```text
group.basic.definition
```

split on `.` and use:

- all but the last segment as directories
- the last segment as the basename

Resulting stem:

```text
group/basic/definition
```

The canonical sibling files are then:

```text
group/basic/definition.md
group/basic/definition.json
```

## File pairing rules

A valid stored node requires both canonical siblings:

- Markdown body file
- metadata JSON file

Current storage and validation code explicitly report:

- orphan markdown with no metadata
- orphan metadata with no markdown
- metadata id / path-derived id mismatches

## Markdown behavior

Markdown bodies are stored as plain UTF-8 text.

### On write

`AFTK.KnowledgeBase.Serialization.writeMarkdownFile` and atomic write helpers:

- normalize `\r\n` and `\r` to `\n`
- ensure a trailing newline

### On read

`readMarkdownFile` normalizes line endings to `\n`.

The body is otherwise treated as ordinary text.
There is currently no Markdown parsing or semantic normalization layer.

## Metadata behavior

Metadata is strict JSON parsed by `parseNodeMetadataText`.

### Reader behavior

Current reader rules:

- reject unknown fields
- require mandatory fields
- reject unsupported schema versions
- parse `NodeId`, enums, timestamps, relationships, and `leanRefs` structurally
- default omitted `kind` to `note`
- default omitted `status` to `draft`
- default omitted arrays to empty arrays

### Writer behavior

`renderNodeMetadata` emits deterministic field order and omits default/empty fields where appropriate.

Current field order:

1. `schemaVersion`
2. `id`
3. `title`
4. `kind` if not default
5. `status` if not default
6. `summary` if present
7. `tags` if nonempty
8. `authors` if nonempty
9. `createdAt` if present
10. `updatedAt` if present
11. `relationships` if nonempty
12. `leanRefs` if nonempty

## Atomic write strategy

`AFTK.KnowledgeBase.Storage` uses a temp-file-plus-rename strategy for manifest, metadata, and Markdown writes.

Operationally:

- create parent directories if needed
- write to a temporary sibling path
- rename into place

This keeps writes simple while avoiding obvious partial-overwrite behavior.

## Implemented mutation semantics

### `initRoot`

Creates:

- the root directory
- `manifest.json`
- `nodes/`
- `.aftk/index/`
- `.aftk/cache/`
- `.aftk/tmp/`

It fails with a conflict error if `manifest.json` already exists.

### `createNode`

Creates both canonical files for a new node.

Defaults:

- body defaults to empty string
- `kind = note`
- `status = draft`
- `createdAt` and `updatedAt` are both set to the creation timestamp

### `setNodeBody`

Rewrites the Markdown body and refreshes `updatedAt` in metadata.

### `replaceNodeMetadata`

Rewrites the full metadata object and refreshes `updatedAt`.
The replacement must preserve the target id.

### `renameNode`

A rename is implemented as:

- load existing node
- rewrite the node at the new canonical paths
- update metadata `id`
- refresh `updatedAt`
- remove the old Markdown and metadata files

Current rename does **not** rewrite other nodes that may reference the old id.
Callers must treat that as an application-level concern.

### `deleteNode`

Removes both canonical files for the node.

## Scanning and enumeration

Whole-root discovery uses `scanCanonicalNodeFiles`.

It recursively walks `nodes/`, groups discovered `.md` and `.json` files by shared stem, and sorts stems deterministically.

Higher-level loaders then build on that:

- `loadAllStoredNodes`
- `loadAllMetadata`

These loaders are intentionally strict and surface orphan or invalid canonical files instead of silently skipping them.

## Validation-relevant invariants

Current storage and validation code check at least these invariants:

- root exists
- manifest exists
- manifest parses
- `nodes/` exists
- path-derived node id is valid
- Markdown/metadata sibling pairing is complete
- metadata id matches path-derived id
- duplicate ids are rejected in whole-root validation
- missing relationship targets are reported in whole-root validation

`validate all` also reports missing `.aftk/` as an informational issue.
That missing internal directory does not by itself make the root invalid.

## Direct editing guidance

The storage format is intentionally human-editable.
If you edit canonical files manually, the safe follow-up command is:

```text
lake exe aftk knowledgebase validate all
```

That is the current supported way to check whether hand-edited storage still satisfies the library's invariants.
