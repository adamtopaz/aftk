# Knowledge-base layer overview

The knowledge-base layer is the implemented foundation of the rewrite.
It is responsible for canonical natural-language storage and for the filesystem-facing operations that higher layers rely on.

Public entrypoints:

- library: `import AFTK.KnowledgeBase`
- CLI: `lake exe aftk knowledgebase ...`

## What is implemented

The current implementation includes:

- strict `NodeId` and `Timestamp` types
- canonical file-backed storage rooted at `knowledgebase/`
- Markdown bodies paired with strict JSON metadata
- storage initialization and node lifecycle operations
- whole-root scanning directly from canonical files
- validation at storage, metadata, node, and whole-root scopes
- direct-scan text search and exact-tag search
- outgoing, incoming, and combined relationship queries
- a help-rich CLI with text and JSON output modes
- a dedicated `lake test` suite

## What is not implemented yet

These areas remain intentionally deferred:

- derived indexing or `reindex` workflows
- repair planning or repair application commands
- a larger malformed-root regression-fixture corpus

That means the current semantics are defined entirely by canonical files, not by caches or indexes.

## Design commitments reflected in the code

### The knowledge base is the prose source of truth

Natural-language content lives in one place:

- Markdown body files
- JSON metadata files

Higher layers may resolve, reference, or present that content, but they should not create competing prose stores.

### Storage is transparent

The current implementation is intentionally easy to inspect in git and in the filesystem.
It uses ordinary directories and files rather than a hidden database.

### Validation is explicit

The library does not quietly normalize or repair invalid canonical data.
Instead it exposes explicit validation reports and CLI exit codes.

## Core data model

### Node identity

A node is identified by a dotted `NodeId`, for example:

- `group.basic.definition`
- `algebra.monoid.definition`
- `analysis.uniform_continuity`

Current `NodeId` rules:

- nonempty
- dot-separated segments
- no whitespace
- no `/` or `\`
- each segment starts with a lowercase ASCII letter
- remaining segment characters are lowercase ASCII letters, digits, or `_`

### Node contents

Each logical node consists of:

- `NodeMetadata`
- a Markdown body string

The main metadata fields currently used are:

- `id`
- `title`
- `kind`
- `status`
- `summary?`
- `tags`
- `authors`
- `createdAt?`
- `updatedAt?`
- `relationships`
- `leanRefs`

### Node kinds

Implemented `NodeKind` values:

- `note`
- `definition`
- `theorem`
- `proofSketch`
- `example`
- `explanation`
- `concept`
- `documentation`

### Node statuses

Implemented `NodeStatus` values:

- `draft`
- `active`
- `deprecated`
- `archived`

### Relationship kinds

Implemented `RelationshipKind` values:

- `relatedTo`
- `dependsOn`
- `elaborates`
- `refines`
- `exampleOf`
- `hasExample`
- `seeAlso`

## Storage layout

By default, the CLI resolves the root as:

```text
knowledgebase/
```

relative to the current working directory.

Canonical layout:

```text
knowledgebase/
  manifest.json
  nodes/
    ...
  .aftk/
    index/
    cache/
    tmp/
```

Only these locations are canonical today:

- `knowledgebase/manifest.json`
- `knowledgebase/nodes/**`

`.aftk/` exists as reserved internal space.
Its subdirectories are created by `init`, but the current implementation does not yet populate indexing or repair data there.

For a node id such as `group.basic.definition`, the canonical file pair is:

```text
knowledgebase/nodes/group/basic/definition.md
knowledgebase/nodes/group/basic/definition.json
```

## CLI surface

The public CLI is:

```text
lake exe aftk knowledgebase ...
```

Implemented command families:

- `init`
- `status`
- `list`
- `show`
- `create`
- `rename`
- `delete`
- `body show`
- `body set`
- `metadata show`
- `metadata replace`
- `metadata validate`
- `validate storage`
- `validate node`
- `validate all`
- `search text`
- `search tag`
- `relationships outgoing`
- `relationships incoming`
- `relationships related`

Global flags:

- `--root <path>`
- `--format text|json`
- `--help`

## Typical workflow

Initialize a root:

```text
lake exe aftk knowledgebase init
```

Create a node:

```text
lake exe aftk knowledgebase create topology.open_cover \
  --title "Open cover" \
  --kind definition \
  --summary "Definition of an open cover."
```

Set the body from stdin:

```text
lake exe aftk knowledgebase body set topology.open_cover --stdin
```

Inspect it:

```text
lake exe aftk knowledgebase show topology.open_cover
lake exe aftk knowledgebase show topology.open_cover --metadata
lake exe aftk knowledgebase show topology.open_cover --paths
```

Validate the whole root:

```text
lake exe aftk knowledgebase validate all
```

Search:

```text
lake exe aftk knowledgebase search text "open cover"
lake exe aftk knowledgebase search tag topology
```

## Important behavioral details

### `status` is probe-like

`status` can describe an uninitialized root.
It does not require the root to exist already.

### Other commands require initialization

Every command except `init` and probe-like status handling assumes the root has already been initialized and that `manifest.json` is present.

### Whole-root semantics are direct-scan

Search and validation load canonical files directly.
There is no hidden index that changes result semantics.

### Validation warnings and info do not force failure

The CLI exits with code `4` only when a validation report contains an error-severity issue.
A report containing only warnings or informational issues still exits successfully.

### Mutation commands update timestamps

`create`, `body set`, `metadata replace`, and `rename` refresh `updatedAt`.
`create` also initializes `createdAt`.

## Output model

### Text output

Text output is optimized for humans and differs by command.
Examples:

- `list` prints tab-separated one-line summaries
- `show` prints metadata, canonical paths, and body
- validation prints a short summary plus issue lines

### JSON output

Knowledge-base CLI JSON uses a stable top-level envelope:

- `command`
- `root`
- `ok`
- `result` or `error`
- `warnings`

This is the more automation-friendly contract.

## Relationship to higher layers

The current higher-layer assumptions are:

- `NodeId` is the stable cross-layer handle for prose knowledge
- canonical prose lives in the knowledge base only
- the informal layer resolves `informal[...]` through this layer
- the server layer should reuse this layer rather than reading ad hoc sidecar formats
- `leanRefs` is a metadata field the knowledge-base layer preserves structurally, but informal tracking is a separate Lean-environment concern rather than an automatically synchronized metadata view

## Where to read next

- `docs/knowledgebase/storage.md`
- `docs/knowledgebase/cli.md`
- `docs/knowledgebase/library.md`
- `docs/knowledgebase/testing.md`
