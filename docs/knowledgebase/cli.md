# Knowledgebase CLI reference

The public CLI is:

```text
lake exe aftk knowledgebase ...
```

Help is available at both entrypoints:

```text
lake exe aftk --help
lake exe aftk knowledgebase --help
lake exe aftk knowledgebase <command> --help
```

## Global options

Supported global options:

- `--root <path>`
- `--format text|json`
- `--help`

Every command and nested subcommand also supports `--help`.
For example:

```text
lake exe aftk knowledgebase create --help
lake exe aftk knowledgebase body set --help
lake exe aftk knowledgebase validate node --help
```

## Root commands

### `init`

```text
lake exe aftk knowledgebase init
lake exe aftk knowledgebase --root /tmp/my-kb init
```

Creates:

- the root directory
- `manifest.json`
- `nodes/`
- `.aftk/index/`
- `.aftk/cache/`
- `.aftk/tmp/`

### `status`

```text
lake exe aftk knowledgebase status
```

Reports:

- root path
- initialization status
- schema version
- manifest kind
- node count
- presence of internal directories

## Core node commands

### `list`

```text
lake exe aftk knowledgebase list
lake exe aftk knowledgebase list --prefix topology
lake exe aftk knowledgebase list --kind definition
lake exe aftk knowledgebase list --status draft
lake exe aftk knowledgebase list --tag topology
```

### `show <id>`

```text
lake exe aftk knowledgebase show topology.open_cover
lake exe aftk knowledgebase show topology.open_cover --body
lake exe aftk knowledgebase show topology.open_cover --metadata
lake exe aftk knowledgebase show topology.open_cover --paths
```

Default behavior shows metadata, paths, and body together.

### `create <id>`

```text
lake exe aftk knowledgebase create topology.open_cover --title "Open cover"
lake exe aftk knowledgebase create topology.open_cover --title "Open cover" --kind definition
lake exe aftk knowledgebase create topology.open_cover --title "Open cover" --summary "Definition of an open cover."
lake exe aftk knowledgebase create topology.open_cover --title "Open cover" --tag topology --author aftk
lake exe aftk knowledgebase create topology.open_cover --title "Open cover" --body-file draft.md
lake exe aftk knowledgebase create topology.open_cover --title "Open cover" --body-stdin
```

### `rename <old-id> <new-id>`

```text
lake exe aftk knowledgebase rename topology.old_name topology.new_name
```

### `delete <id>`

```text
lake exe aftk knowledgebase delete topology.open_cover
```

## Body commands

### `body show <id>`

```text
lake exe aftk knowledgebase body show topology.open_cover
```

### `body set <id>`

```text
lake exe aftk knowledgebase body set topology.open_cover --from draft.md
lake exe aftk knowledgebase body set topology.open_cover --stdin
```

## Metadata commands

### `metadata show <id>`

```text
lake exe aftk knowledgebase metadata show topology.open_cover
```

### `metadata replace <id>`

```text
lake exe aftk knowledgebase metadata replace topology.open_cover --from metadata.json
lake exe aftk knowledgebase metadata replace topology.open_cover --stdin
```

### `metadata validate <id>`

```text
lake exe aftk knowledgebase metadata validate topology.open_cover
```

## Validation commands

### `validate storage`

```text
lake exe aftk knowledgebase validate storage
```

### `validate node <id>`

```text
lake exe aftk knowledgebase validate node topology.open_cover
```

### `validate all`

```text
lake exe aftk knowledgebase validate all
```

## Search commands

### `search text <query>`

```text
lake exe aftk knowledgebase search text "open cover"
lake exe aftk knowledgebase search text "open cover" --limit 20
```

Current semantics:

- case-insensitive substring search
- searches node body, metadata title, and metadata summary
- deterministic node-ID ordering
- optional limit

### `search tag <tag>`

```text
lake exe aftk knowledgebase search tag topology
lake exe aftk knowledgebase search tag topology --limit 20
```

Current semantics:

- exact tag match
- deterministic node-ID ordering
- optional limit

## Relationship commands

### `relationships outgoing <id>`

```text
lake exe aftk knowledgebase relationships outgoing topology.open_cover
```

### `relationships incoming <id>`

```text
lake exe aftk knowledgebase relationships incoming topology.open_set
```

### `relationships related <id>`

```text
lake exe aftk knowledgebase relationships related topology.open_cover
```

## JSON output

All commands accept `--format json`.

The top-level shape is:

```json
{
  "command": "show",
  "root": "/abs/path/to/knowledgebase",
  "ok": true,
  "result": {},
  "warnings": []
}
```

Failures use:

```json
{
  "command": "show",
  "root": "/abs/path/to/knowledgebase",
  "ok": false,
  "error": {
    "code": "node.notFound",
    "message": "Node not found: topology.open_cover"
  },
  "warnings": []
}
```

## Exit codes

Current exit-code policy:

- `0` — success
- `1` — generic operational failure
- `2` — usage error
- `3` — not found
- `4` — validation failure
- `5` — conflict or already exists
