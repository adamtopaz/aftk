# Knowledge-base CLI reference

The public command is:

```text
lake exe aftk knowledgebase ...
```

This CLI is implemented in `AFTK/KnowledgeBase/Cli/*` and dispatched from the top-level `aftk` executable.

## Help system

Help is available at multiple levels:

```text
lake exe aftk --help
lake exe aftk knowledgebase --help
lake exe aftk knowledgebase <command> --help
```

Examples:

```text
lake exe aftk knowledgebase create --help
lake exe aftk knowledgebase body set --help
lake exe aftk knowledgebase validate node --help
```

## Global options

All knowledge-base commands accept:

- `--root <path>`
- `--format text|json`
- `--help`

Notes:

- `--root` changes the resolved knowledge-base root
- `--format` only affects successful/failed command rendering; it does not change command semantics
- invalid global options are usage errors with exit code `2`

## Exit codes

Current exit-code policy comes from `KnowledgeBaseError` plus validation handling:

- `0` — success
- `1` — generic operational failure
- `2` — usage error
- `3` — not found
- `4` — validation failure
- `5` — conflict / already exists

For validation commands specifically:

- exit code `4` means the report contains at least one error-severity issue
- reports with only warnings or infos still exit `0`

## Command families

### `init`

Initialize a root:

```text
lake exe aftk knowledgebase init
lake exe aftk knowledgebase --root /tmp/my-kb init
```

Behavior:

- creates `manifest.json`
- creates `nodes/`
- creates `.aftk/index/`, `.aftk/cache/`, `.aftk/tmp/`
- fails with a conflict if the root is already initialized

### `status`

Probe root status:

```text
lake exe aftk knowledgebase status
lake exe aftk knowledgebase --root tests/informal/knowledgebase-fixtures/basic-valid status
```

Reports:

- resolved root path
- whether the root is initialized
- manifest schema version and kind
- discovered paired-node count
- presence of internal directories

`status` is intentionally more forgiving than other commands and can describe an uninitialized root.

### `list`

List nodes:

```text
lake exe aftk knowledgebase list
lake exe aftk knowledgebase list --prefix group.basic
lake exe aftk knowledgebase list --kind definition
lake exe aftk knowledgebase list --status active
lake exe aftk knowledgebase list --tag algebra
```

Available filters:

- `--prefix <prefix>`
- `--kind <kind>`
- `--status <status>`
- `--tag <tag>`

Filters are combined conjunctively.

### `show <id>`

Show a stored node:

```text
lake exe aftk knowledgebase show topology.open_cover
lake exe aftk knowledgebase show topology.open_cover --body
lake exe aftk knowledgebase show topology.open_cover --metadata
lake exe aftk knowledgebase show topology.open_cover --paths
```

Selections:

- default: combined view
- `--body`: Markdown only
- `--metadata`: metadata JSON only
- `--paths`: canonical file paths only

### `create <id>`

Create a node:

```text
lake exe aftk knowledgebase create topology.open_cover --title "Open cover"
lake exe aftk knowledgebase create topology.open_cover --title "Open cover" --kind definition
lake exe aftk knowledgebase create topology.open_cover --title "Open cover" --summary "Definition of an open cover."
lake exe aftk knowledgebase create topology.open_cover --title "Open cover" --tag topology --author aftk
lake exe aftk knowledgebase create topology.open_cover --title "Open cover" --body-file draft.md
lake exe aftk knowledgebase create topology.open_cover --title "Open cover" --body-stdin
```

Create options:

- `--title <title>` — required
- `--kind <kind>`
- `--status <status>`
- `--summary <text>`
- `--tag <tag>` — repeatable
- `--author <author>` — repeatable
- `--body-file <path>`
- `--body-stdin`

Only one body source may be specified.
If neither is given, the node is created with an empty body.

### `rename <old-id> <new-id>`

Rename a node:

```text
lake exe aftk knowledgebase rename topology.old_name topology.new_name
```

Behavior:

- moves the canonical Markdown and metadata files
- rewrites the metadata `id`
- refreshes `updatedAt`
- fails if the target already exists

### `delete <id>`

Delete a node:

```text
lake exe aftk knowledgebase delete topology.open_cover
```

This removes both canonical files for the node.

## Body subcommands

### `body show <id>`

```text
lake exe aftk knowledgebase body show topology.open_cover
```

Prints the normalized Markdown body.

### `body set <id>`

```text
lake exe aftk knowledgebase body set topology.open_cover --from draft.md
lake exe aftk knowledgebase body set topology.open_cover --stdin
```

Options:

- `--from <path>`
- `--stdin`

On success, the current implementation returns the updated stored node view rather than only an acknowledgment.

## Metadata subcommands

### `metadata show <id>`

```text
lake exe aftk knowledgebase metadata show topology.open_cover
```

Prints canonical metadata JSON.

### `metadata replace <id>`

```text
lake exe aftk knowledgebase metadata replace topology.open_cover --from metadata.json
lake exe aftk knowledgebase metadata replace topology.open_cover --stdin
```

Options:

- `--from <path>`
- `--stdin`

The replacement metadata must keep the same node id.
On success, the current implementation returns the updated stored node view.

### `metadata validate <id>`

```text
lake exe aftk knowledgebase metadata validate topology.open_cover
```

Runs metadata-focused validation for one node.

## Validation commands

### `validate storage`

```text
lake exe aftk knowledgebase validate storage
```

Checks root/manifest/storage structure without fully loading every node pair.

### `validate node <id>`

```text
lake exe aftk knowledgebase validate node topology.open_cover
```

Checks the specific node's canonical files plus underlying metadata validation.

### `validate all`

```text
lake exe aftk knowledgebase validate all
```

Runs whole-root validation, including:

- orphan file detection
- invalid path-derived ids
- metadata parse errors
- metadata/path id mismatches
- duplicate node ids
- missing relationship targets

## Search commands

### `search text <query>`

```text
lake exe aftk knowledgebase search text "open cover"
lake exe aftk knowledgebase search text "open cover" --limit 20
```

Current semantics:

- case-insensitive substring matching
- searches body text, title, and summary
- deterministic ordering by canonical scan order
- optional `--limit <n>`

Result hits currently expose:

- `id`
- `title?`
- `summary?`
- `matchedScopes`
- `snippet?`

### `search tag <tag>`

```text
lake exe aftk knowledgebase search tag topology
lake exe aftk knowledgebase search tag topology --limit 20
```

Current semantics:

- exact tag match
- deterministic ordering
- optional `--limit <n>`

## Relationship commands

### `relationships outgoing <id>`

```text
lake exe aftk knowledgebase relationships outgoing group.basic.definition
```

Returns the node's declared outgoing relationships from metadata.

### `relationships incoming <id>`

```text
lake exe aftk knowledgebase relationships incoming algebra.monoid.definition
```

Scans the whole root and returns metadata relationships that point to the target node.

### `relationships related <id>`

```text
lake exe aftk knowledgebase relationships related group.basic.definition
```

Returns both outgoing and incoming relationships.

## Text output

Text output is meant for direct terminal use.
Examples of current behavior:

- `list` prints one node per line as `id<TAB>kind<TAB>status<TAB>title`
- `show` prints a metadata block, paths, and then the body
- search prints human-readable hits with short snippets
- validation prints a summary line plus issue lines

Text output is stable enough for humans, but JSON is the better choice for automation.

## JSON output

Knowledge-base success JSON uses a stable top-level envelope. A typical success shape is:

```json
{
  "command": "show",
  "root": "/abs/path/to/knowledgebase",
  "ok": true,
  "result": { ... },
  "warnings": []
}
```

Failures use the same outer structure with `ok: false` and an `error` object:

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

## Practical examples

Initialize and create:

```text
lake exe aftk knowledgebase init
lake exe aftk knowledgebase create topology.open_cover --title "Open cover" --kind definition
```

Search with JSON output:

```text
lake exe aftk knowledgebase --format json search text open
```

Validate a fixture root:

```text
lake exe aftk knowledgebase --root tests/informal/knowledgebase-fixtures/basic-valid validate all
```
