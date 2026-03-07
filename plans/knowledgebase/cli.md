# Knowledge Base CLI Design

## Status

Design-only component plan for the knowledge base CLI.
This document refines the overall knowledge base plan in `plans/knowledgebase.md` and works together with `plans/knowledgebase/storage.md`, `plans/knowledgebase/node.md`, `plans/knowledgebase/metadata.md`, `plans/knowledgebase/validation.md`, and `plans/knowledgebase/search.md`.

## Component implementation status

- Overall status: Not implemented
- Implemented in code: No
- Last updated basis: design only

## Purpose

This document defines the planned command-line interface for the knowledge base layer.
It is the design target for the Lean CLI that will manage knowledge-base storage, nodes, metadata, validation, search, and relationship traversal.

No code is being added yet.
This file is only a design target for later implementation.

## Design goals

The CLI should:

- expose the knowledge base through a Lean-native command surface
- be convenient for both humans and automation
- use node IDs rather than raw file paths as the primary user-facing identifiers
- align with the storage, node, and metadata designs
- support both readable text output and machine-readable JSON output
- separate common commands from more specialized command families
- grow cleanly as validation, search, and graph-style functionality become richer

## Naming conventions

The CLI command for this layer should be:

```text
lake exe aftk knowledgebase ...
```

The abbreviation `kb` should not be used for the public CLI surface.
Likewise, Lean module and namespace naming for this layer should use `KnowledgeBase` rather than `KB`.

## High-level CLI shape

The top-level invocation pattern should be:

```text
lake exe aftk knowledgebase [global-options] <command> ...
```

The design should use:

- **top-level commands** for the most common operations
- **nested command families** for more specialized operations

This gives a CLI that is easy to use interactively without becoming flat and chaotic as features are added.

## Global options

The initial CLI design should support global options like these:

- `--root <path>` — override the default knowledge-base root
- `--format text|json` — select output format
- `--quiet` — reduce nonessential text output
- `--verbose` — include more operational detail
- `--no-color` — disable colorized human output if color is added later

### Default root

If `--root` is not provided, the CLI should use the default repository-local root described in `plans/knowledgebase/storage.md`:

```text
./knowledgebase
```

### Output format

The CLI should support two broad output modes:

- `text` — human-oriented output
- `json` — machine-oriented output for scripting and higher layers

The JSON output mode should be stable enough for the toolkit and later agent layers to depend on.

## Command design principles

### 1. Node IDs are the main user-facing references

Users should normally refer to nodes by canonical `NodeId` values such as:

- `topology.open_cover`
- `group.basic.definition`

The CLI may expose paths when useful, but paths should not be the main external identifier.

### 2. Common operations should be top-level

Operations such as create, show, list, rename, and delete should be easy to discover and use.

### 3. Specialized operations should be grouped

Metadata, body, relationship, and search operations should be grouped into dedicated command families where that improves clarity.

### 4. Destructive operations should be explicit

Rename and delete should be clearly named and should not be hidden behind ambiguous update behavior.

### 5. Text output should be readable; JSON output should be structured

Human output can prioritize readability.
Machine output should prioritize stability and explicit structure.

## Proposed initial command surface

This section describes the planned initial CLI design.
It is intentionally broader than the very first implementation milestone, but still focused enough to be realistic.

### Root and storage commands

#### `init`

Initialize a knowledge-base root.

```text
lake exe aftk knowledgebase init
lake exe aftk knowledgebase init --root /path/to/knowledgebase
```

Responsibilities:

- create `knowledgebase/`
- create `manifest.json`
- create `nodes/`
- create `.aftk/`

#### `status`

Show high-level information about the knowledge-base root.

```text
lake exe aftk knowledgebase status
```

Expected information:

- resolved root path
- manifest schema version
- whether the root appears initialized
- basic node counts if cheap to compute
- whether derived internal directories exist

### Core node commands

#### `list`

List nodes in the knowledge base.

```text
lake exe aftk knowledgebase list
lake exe aftk knowledgebase list --prefix topology
lake exe aftk knowledgebase list --kind definition
lake exe aftk knowledgebase list --status draft
lake exe aftk knowledgebase list --tag topology
```

Initial filtering support should be lightweight and composable.

#### `show <id>`

Show a node.

```text
lake exe aftk knowledgebase show topology.open_cover
lake exe aftk knowledgebase show topology.open_cover --body
lake exe aftk knowledgebase show topology.open_cover --metadata
lake exe aftk knowledgebase show topology.open_cover --paths
```

Default behavior should present a readable combined view.
Optional flags can narrow the output to body, metadata, or resolved storage paths.

#### `create <id>`

Create a node.

```text
lake exe aftk knowledgebase create topology.open_cover --title "Open cover"
lake exe aftk knowledgebase create topology.open_cover --title "Open cover" --kind definition
lake exe aftk knowledgebase create topology.open_cover --title "Open cover" --body-file draft.md
lake exe aftk knowledgebase create topology.open_cover --title "Open cover" --body-stdin
```

Initial create behavior should:

- validate the node ID
- resolve canonical storage paths
- fail if the node already exists unless overwrite behavior is explicitly requested later
- create both the Markdown and JSON files
- initialize required metadata fields

#### `rename <old-id> <new-id>`

Rename a node by changing its canonical ID.

```text
lake exe aftk knowledgebase rename topology.old_name topology.new_name
```

This should be treated as an identity-changing operation.
It must update both metadata and storage paths coherently.

#### `delete <id>`

Delete a node.

```text
lake exe aftk knowledgebase delete topology.open_cover
```

The initial CLI can keep deletion simple and explicit.
If safety flags such as `--dry-run` or `--yes` are later needed, they can be added without changing the command family.

### Body commands

The Markdown body is important enough to justify a dedicated command family.
This avoids forcing all edits through a single overly generic `update` command.

#### `body show <id>`

```text
lake exe aftk knowledgebase body show topology.open_cover
```

#### `body set <id>`

```text
lake exe aftk knowledgebase body set topology.open_cover --from draft.md
lake exe aftk knowledgebase body set topology.open_cover --stdin
```

The initial design should prefer explicit body replacement over complicated patch semantics.
More sophisticated editing commands can be added later.

### Metadata commands

Metadata is structured enough to justify its own command family.

#### `metadata show <id>`

```text
lake exe aftk knowledgebase metadata show topology.open_cover
```

This should print just the metadata, in text or JSON format.

#### `metadata replace <id>`

```text
lake exe aftk knowledgebase metadata replace topology.open_cover --from metadata.json
lake exe aftk knowledgebase metadata replace topology.open_cover --stdin
```

This command should replace the full metadata object subject to validation.
That is simpler and safer for an initial implementation than exposing a rich patch language immediately.

#### `metadata validate <id>`

```text
lake exe aftk knowledgebase metadata validate topology.open_cover
```

This should validate just the node’s metadata structure and report problems clearly.

### Validation commands

Validation should be a first-class part of the CLI.

#### `validate storage`

```text
lake exe aftk knowledgebase validate storage
```

Validate the root layout, manifest, and storage-level invariants.

#### `validate node <id>`

```text
lake exe aftk knowledgebase validate node topology.open_cover
```

Validate a single node, including pairing and identity invariants.

#### `validate all`

```text
lake exe aftk knowledgebase validate all
```

Validate the full knowledge base.
This may include broken-reference detection and broader consistency checks.

### Search commands

Search should have its own command family so that discovery can grow over time without cluttering the root command surface.

#### `search text <query>`

```text
lake exe aftk knowledgebase search text "open cover"
```

Initial behavior should be simple full-text search over canonical content.

#### `search tag <tag>`

```text
lake exe aftk knowledgebase search tag topology
```

This provides a lightweight metadata-driven query path.

### Relationship commands

Because node relationships are a first-class part of metadata, relationship traversal should have explicit CLI support.

#### `relationships outgoing <id>`

```text
lake exe aftk knowledgebase relationships outgoing topology.open_cover
```

Show the relationships stored directly in the node’s metadata.

#### `relationships incoming <id>`

```text
lake exe aftk knowledgebase relationships incoming topology.open_cover
```

Show other nodes that point to the given node.
This may require scanning or an index, but it is still a natural part of the CLI design.

#### `relationships related <id>`

```text
lake exe aftk knowledgebase relationships related topology.open_cover
```

A convenience command that can present a broader relationship view, potentially combining incoming and outgoing edges.

## Commands intentionally deferred from the first implementation

The CLI design leaves room for later commands such as:

- `reindex`
- `repair`
- richer metadata field editing commands
- interactive editor-based commands
- import/export commands
- batch mutation commands
- graph/path traversal commands beyond simple incoming/outgoing listing

These are plausible later extensions, but they should not block the initial implementation.

## Recommended first implementation slice

The first usable implementation of the CLI should likely prioritize:

1. `init`
2. `status`
3. `list`
4. `show`
5. `create`
6. `body show`
7. `body set`
8. `metadata show`
9. `metadata replace`
10. `validate node`
11. `validate storage`

After that, the next additions should likely be:

- `rename`
- `delete`
- `validate all`
- `search text`
- `search tag`
- `relationships outgoing`
- `relationships incoming`

## Output model

### Text output

Text output should be concise, readable, and suitable for interactive terminal use.
It may include headings or labeled sections where that improves clarity.

### JSON output

JSON output should be structured and predictable.
A command result should generally include information such as:

- the command that ran
- the resolved root path
- the primary result payload
- warnings, if any

The exact JSON schema can be refined during implementation, but the principle should be to provide stable machine-readable output rather than dumping ad hoc text.

## Error handling and exit behavior

The CLI should clearly distinguish between:

- usage errors
- storage initialization errors
- node-not-found errors
- validation failures
- conflicts such as trying to create an existing node
- internal/unexpected errors

A reasonable initial exit-code strategy would be:

- `0` — success
- `1` — generic operational failure
- `2` — usage or argument error
- `3` — not found
- `4` — validation failure
- `5` — conflict or already exists

The exact exit-code scheme can still be refined later, but it should be explicit and consistent.

## Proposed Lean-level command model

A possible Lean-side command model could look conceptually like this:

```lean
namespace AFTK.KnowledgeBase

inductive OutputFormat
  | text
  | json

structure GlobalOptions where
  root? : Option System.FilePath := none
  format : OutputFormat := .text
  quiet : Bool := false
  verbose : Bool := false
  noColor : Bool := false

inductive InputSource
  | stdin
  | file (path : System.FilePath)

inductive BodyCommand
  | show (id : NodeId)
  | set (id : NodeId) (source : InputSource)

inductive MetadataCommand
  | show (id : NodeId)
  | replace (id : NodeId) (source : InputSource)
  | validate (id : NodeId)

inductive ValidateCommand
  | storage
  | node (id : NodeId)
  | all

inductive SearchCommand
  | text (query : String)
  | tag (tag : String)

inductive RelationshipCommand
  | outgoing (id : NodeId)
  | incoming (id : NodeId)
  | related (id : NodeId)

inductive Command
  | init
  | status
  | list
  | show (id : NodeId)
  | create (id : NodeId)
  | rename (oldId : NodeId) (newId : NodeId)
  | delete (id : NodeId)
  | body (cmd : BodyCommand)
  | metadata (cmd : MetadataCommand)
  | validate (cmd : ValidateCommand)
  | search (cmd : SearchCommand)
  | relationships (cmd : RelationshipCommand)

end AFTK.KnowledgeBase
```

This is only a conceptual design, not a commitment to a specific parser library or exact implementation type.

## Open questions for later refinement

- Should `show` default to combined output, or should it require `--body` / `--metadata` selection?
- Should `create` accept more metadata fields directly, or stay intentionally minimal?
- When should overwrite or force flags be introduced?
- Should full-metadata replacement remain the main mutation primitive, or should field-level editing be added early?
- Should `relationships incoming` require an index, or should it be allowed to scan canonically stored nodes in v1?
- How much of the JSON result schema should be standardized immediately?

## Summary

The knowledge base CLI should use the public command surface:

```text
lake exe aftk knowledgebase ...
```

It should combine a small set of ergonomic top-level commands with nested families for bodies, metadata, validation, search, and relationships.

The initial design is centered on explicit node-ID-based operations, stable JSON output for automation, readable text output for humans, and clean alignment with the storage, node, and metadata plans.