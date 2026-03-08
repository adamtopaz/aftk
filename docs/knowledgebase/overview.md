# Knowledgebase layer overview

The knowledgebase layer is the implemented first layer of the `aftk` rewrite.
It is the canonical store for natural-language knowledge.

## What exists today

The current implementation provides:

- canonical file-backed storage under `knowledgebase/`
- Markdown bodies and JSON metadata for each node
- validated dotted node IDs such as `topology.open_cover`
- structured relationships between nodes
- a Lean CLI at `lake exe aftk knowledgebase ...`
- direct-scan validation and search
- a `lake test` driver with unit, storage, validation, search, and CLI coverage

The main deferred areas are:

- derived indexing and reindex workflows
- repair planning and repair application commands
- a larger regression-fixture suite for malformed roots

## Quick start

Initialize a knowledgebase root:

```text
lake exe aftk knowledgebase init
```

Create a node:

```text
lake exe aftk knowledgebase create topology.open_cover --title "Open cover" --kind definition
```

Set its body from stdin:

```text
lake exe aftk knowledgebase body set topology.open_cover --stdin
```

Show it:

```text
lake exe aftk knowledgebase show topology.open_cover
```

Validate everything:

```text
lake exe aftk knowledgebase validate all
```

Search:

```text
lake exe aftk knowledgebase search text "open cover"
lake exe aftk knowledgebase search tag topology
```

Run the test suite:

```text
lake test
```

## Storage summary

The canonical root is:

```text
knowledgebase/
```

with this layout:

```text
knowledgebase/
  manifest.json
  nodes/
    topology/
      open_cover.md
      open_cover.json
  .aftk/
    index/
    cache/
    tmp/
```

Canonical data:

- `knowledgebase/manifest.json`
- `knowledgebase/nodes/**`

Derived/internal data:

- `knowledgebase/.aftk/**`

## Node model

Each node is stored as two sibling files with a shared stem:

- `<stem>.md` — Markdown body
- `<stem>.json` — structured metadata

Examples:

- `topology.open_cover` -> `knowledgebase/nodes/topology/open_cover.md`
- `topology.open_cover` -> `knowledgebase/nodes/topology/open_cover.json`

## Implemented command families

Top-level:

- `init`
- `status`
- `list`
- `show`
- `create`
- `rename`
- `delete`

Nested families:

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

## Output modes

All CLI commands support:

- `--format text`
- `--format json`

JSON output uses a stable top-level envelope with fields like:

- `command`
- `root`
- `ok`
- `result`
- `error`
- `warnings`

## Higher-layer assumptions

The current knowledgebase layer is intended to expose these stable assumptions upward:

- node identity is carried by `NodeId`
- canonical natural-language content lives only in the knowledgebase
- higher layers should reference nodes by ID rather than inventing alternate prose stores
- validation and search semantics are defined in terms of canonical files, not caches

For more detail, see the companion documents in this folder.
