# Informal CLI Design

## Status

Component plan and implementation-status document for the informal-layer CLI.
This document refines the overall informal-layer plan in `plans/informal.md` and works together with `plans/informal/elaboration.md`, `plans/informal/references.md`, `plans/informal/tracking.md`, `plans/informal/dependencies.md`, `plans/informal/presentation.md`, `plans/informal/layout.md`, and `plans/informal/testing.md`.

## Component implementation status

- Overall status: Implemented (initial v1)
- Implemented in code: Yes
- Last updated basis: repository now provides `AFTK.Informal.Cli.*`, top-level `lake exe aftk informal ...` dispatch, JSON/text rendering, and tested environment-backed and presentation-backed commands.

## Purpose

This document defines the planned command-line interface for the informal layer.
It is the design target for the Lean CLI that will expose:

- declaration-level informal-reference tracking
- reverse lookup from references to declarations
- derived declaration and reference dependency views
- knowledge-base-backed presentation rendering for referenced nodes

AFTK intentionally differs from the earlier `informalize` CLI in one major way:

- the CLI should no longer manage a separate `informal/...` markdown/json sidecar store
- instead, it should query and present references that resolve through the knowledge base

## Design goals

The CLI should:

- expose the informal layer through a Lean-native command surface
- be useful for both humans and automation
- make declaration↔reference linkage easy to inspect
- expose the dependency views defined by the informal layer without pretending to be a full workflow orchestrator
- support both readable text output and stable machine-readable JSON output
- stay mostly query-oriented in v1 rather than becoming a mutation-heavy interface
- reuse the knowledge-base layer for all canonical node resolution and presentation content

## Naming conventions

The CLI command for this layer should be:

```text
lake exe aftk informal ...
```

The public CLI should use `informal`, not `informalize`.
Likewise, Lean module and namespace naming for this layer should be based on `Informal`, not on the old `Informalize` module tree.

## High-level CLI shape

The top-level invocation pattern should be:

```text
lake exe aftk informal [global-options] <command> ...
```

The design should keep the CLI relatively flat in v1, because the main command groups are already clear:

- tracked declaration queries
- tracked reference queries
- dependency queries
- presentation queries

## Query-first CLI philosophy

Unlike the earlier `informalize` CLI, the AFTK informal CLI should be primarily read-only in v1.

### Why

The canonical content and metadata now live in the knowledge base.
So the informal layer should not introduce a large mutation surface for editing natural-language data or workflow metadata.

### Consequence

The v1 informal CLI should focus on:

- querying tracked declarations and references
- rendering dependency views
- rendering knowledge-base-backed presentation views

If a user wants to mutate node content or metadata, they should use:

```text
lake exe aftk knowledgebase ...
```

and if they want to change where `informal[...]` appears, they should edit Lean source.

## Global options

The initial CLI design should support global options like these:

- `--module <Module.Name>` — import one module for tracking/dependency queries (repeatable)
- `--root <path>` — override the default knowledge-base root for commands that resolve references against the knowledge base
- `--format text|json` — select output format
- `--help` — show help for the current command or subcommand

## Two command classes

The CLI has two natural classes of commands.

### 1. Environment-backed tracked-state commands

These commands query the persistent environment extension and derived dependency views.
They require at least one `--module` argument.

These include:

- `status`
- `decls`
- `decl <Decl.Name>`
- `refs`
- `ref <NodeId>`
- `deps`

### 2. Knowledge-base-backed presentation commands

These commands render presentation views for specific referenced nodes.
They do not require `--module`, because they operate directly on knowledge-base references.

These include:

- `present <NodeId>`

This split keeps the CLI model simple and avoids overloading every command with both module and root requirements.

## Module-loading model

For tracked-state and dependency queries, the CLI should import the requested modules into a Lean environment and run the informal-layer queries there.

### Required rule

All tracked-state commands should require at least one `--module <Module.Name>`.
If no module is supplied, the command should fail with a usage error.

### Repeatable modules

`--module` should be repeatable.
When multiple modules are supplied, the CLI should import them together into one environment and query the merged extension state and dependency views over that environment.

### Environment caching

An implementation may cache imported environments keyed by the requested module list, as the earlier CLI does.
That is an implementation optimization, not a semantic requirement.

### Lean import implementation note

Core Lean behavior matters here.
Environment-backed informal commands should follow the normal import path used by CLI-style tools:

- `Lean.findSysroot`
- `Lean.initSearchPath`
- `Lean.enableInitializersExecution`
- `Lean.importModules ... (loadExts := true)`

The `loadExts := true` part is important because tracked-state commands depend on the informal persistent environment extension being loaded from imported modules.
By contrast, Lean’s `withImportModules` helper deliberately disables extension loading, so it is not the right helper for these commands.

### No separate informal-root discovery

The tracked-state commands should not invent a second filesystem root or `informal/` discovery scheme.
They operate on Lean environments plus the persistent extension state.

## Knowledge-base root handling

Presentation commands need a knowledge-base root in order to resolve node ids.

### Default root policy

The informal CLI should reuse the knowledge-base layer’s root policy.
If `--root` is not provided, it should use the same default knowledge-base root behavior as the knowledge-base CLI.

### No separate informal content root

The informal CLI should not introduce its own `informal/` root or sidecar path convention.
All canonical node resolution should go through the knowledge-base layer.

## Output format

The CLI should support two broad output modes:

- `text` — human-oriented output
- `json` — machine-oriented output for scripting and higher layers

JSON output is part of the MVP, not a later enhancement.
As with the knowledge-base CLI, the JSON output should be treated as a stronger compatibility boundary than the exact text formatting.

## Command design principles

### 1. Use declarations and node ids as the user-facing identifiers

The informal CLI should primarily expose:

- Lean declaration names
- knowledge-base node ids

It should not ask users to reason in terms of internal environment-extension payloads, source positions, or filesystem paths.

### 2. Preserve declaration-level public semantics

Because the tracking layer is declaration-level, the CLI should not expose public per-site occurrence commands in v1.

### 3. Keep dependency views explicit about what they mean

The CLI should distinguish:

- declaration dependency views
- reference dependency views

and should not collapse them together or present them as a general-purpose workflow graph.

### 4. Keep presentation commands separate from tracking commands

The command that renders a node presentation should be explicit.
This avoids hiding knowledge-base resolution work inside otherwise simple tracking queries.

### 5. Avoid mutation-heavy command families in v1

The informal layer is not the owner of canonical natural-language data.
The CLI should reflect that boundary.

## Proposed initial command surface

The following initial command surface is recommended.

## `status`

Show high-level tracking statistics for the imported modules.

```text
lake exe aftk informal status --module My.Project.Blueprint
```

Expected information:

- number of tracked declarations
- number of unique tracked references
- maybe the number of declarations with more than one tracked reference if cheap and useful

The command should not report “declarations with empty references,” because bare `informal` support is removed.

## `decls`

List tracked declarations and their referenced node ids.

```text
lake exe aftk informal decls --module My.Project.Blueprint
lake exe aftk informal decls --module My.Project.Blueprint --prefix My.Project.Blueprint.Algebra
lake exe aftk informal decls --module My.Project.Blueprint --ref group.basic.definition
```

Recommended initial filters:

- `--prefix <Decl.Name.Prefix>` — restrict by declaration-name prefix
- `--ref <NodeId>` — show only declarations referencing a given node id

Each row should include:

- declaration name
- reference count
- referenced node ids

## `decl <Decl.Name>`

Show one tracked declaration and its referenced node ids.

```text
lake exe aftk informal decl My.Project.Blueprint.Algebra.groupDef --module My.Project.Blueprint
```

Output should include:

- declaration name
- reference count
- referenced node ids in deterministic order

If the declaration is not tracked, the command should fail with a clear not-found-style message.

## `refs`

List tracked informal references and the declarations that reference them.

```text
lake exe aftk informal refs --module My.Project.Blueprint
lake exe aftk informal refs --module My.Project.Blueprint --prefix group.basic
```

Recommended initial filters:

- `--prefix <NodeIdPrefix>` — restrict by node-id prefix

Each row should include:

- node id
- declaration count
- referencing declaration names

This is the declaration-level reverse index over tracked references.

## `ref <NodeId>`

Show one tracked informal reference and the declarations that reference it.

```text
lake exe aftk informal ref group.basic.definition --module My.Project.Blueprint
```

Output should include:

- node id
- declaration count
- referencing declarations in deterministic order

If the reference is not tracked in the imported modules, the command should return a clear not-found-style error or empty-result convention depending on the final CLI consistency decision. The recommended v1 CLI choice is a not-found-style command failure for targeted commands.

## `deps`

Show derived dependency views.

```text
lake exe aftk informal deps --module My.Project.Blueprint
lake exe aftk informal deps --module My.Project.Blueprint --by decl
lake exe aftk informal deps --module My.Project.Blueprint --by ref
lake exe aftk informal deps --module My.Project.Blueprint --by ref --only-leaves
```

Recommended initial modes:

- `--by decl` — declaration dependency view
- `--by ref` — projected reference dependency view

Recommended initial optional flag:

- `--only-leaves` — restrict output to empty-dependency rows in the selected view

### `deps --by decl`

This should render rows of the form:

- tracked declaration
- tracked declarations it transitively depends on

and optionally a leaf section listing declarations with empty dependency sets.

### `deps --by ref`

This should render rows of the form:

- tracked reference
- tracked references induced by dependent declarations

and optionally a leaf section listing references with empty dependency sets.

### Important wording rule

The CLI should describe these as dependency leaves or empty-dependency rows, not as the full workflow frontier.
That avoids overstating what the informal layer computes.

## `present <NodeId>`

Render a knowledge-base-backed presentation view for one informal reference.

```text
lake exe aftk informal present group.basic.definition
lake exe aftk informal present group.basic.definition --mode compact
lake exe aftk informal present group.basic.definition --mode rich
lake exe aftk informal present group.basic.definition --mode rich --body preview
lake exe aftk informal present group.basic.definition --mode rich --body full
```

This command should:

- validate the node id as an informal reference
- resolve it through the knowledge-base layer
- render either the compact or richer presentation payload defined in `plans/informal/presentation.md`

Recommended initial options:

- `--mode compact|rich` — select compact vs richer presentation mode
- `--body none|preview|full` — select body rendering policy when `--mode rich` is used

### Default behavior

The recommended v1 default is:

- `--mode rich`
- `--body preview`

That makes the explicit presentation command more informative than ordinary term-site hover, while still keeping output bounded by default.

## Command classes intentionally absent in v1

The following command families should be intentionally absent from the first informal CLI:

- metadata mutation commands
- ad hoc filesystem path commands
- per-site occurrence inspection commands
- full workflow frontier/prioritization commands
- knowledge-base node editing commands

Those belong either to the knowledge-base CLI or to higher orchestration layers.

## Output model

The CLI should provide both text and JSON output for all major commands.

## Text output

Text output should be concise and readable.
It should favor simple sections and stable ordering over decorative formatting.

## JSON output

JSON output should be structured for automation.
A good pattern is a stable top-level object containing:

- `command`
- command-specific parameters such as `modules`, `mode`, or `target`
- `data`

### Example envelopes

#### `status`

```json
{
  "command": "status",
  "modules": ["My.Project.Blueprint"],
  "data": {
    "trackedDeclarations": 12,
    "trackedReferences": 8
  }
}
```

#### `decl`

```json
{
  "command": "decl",
  "modules": ["My.Project.Blueprint"],
  "target": "My.Project.Blueprint.Algebra.groupDef",
  "data": {
    "declName": "My.Project.Blueprint.Algebra.groupDef",
    "refCount": 2,
    "refs": [
      "group.basic.definition",
      "algebra.monoid.definition"
    ]
  }
}
```

#### `deps --by ref`

```json
{
  "command": "deps",
  "modules": ["My.Project.Blueprint"],
  "mode": "ref",
  "data": {
    "rows": [
      {
        "ref": "group.basic.definition",
        "dependencies": ["algebra.monoid.definition"]
      }
    ],
    "leaves": ["algebra.monoid.definition"]
  }
}
```

#### `present`

```json
{
  "command": "present",
  "target": "group.basic.definition",
  "mode": "rich",
  "bodyMode": "preview",
  "data": {
    "summary": {
      "ref": "group.basic.definition",
      "title": "Definition of group",
      "kind": "definition",
      "status": "active",
      "summary": "A group is a monoid in which every element has an inverse."
    },
    "body": {
      "kind": "preview",
      "truncated": true,
      "text": "..."
    }
  }
}
```

The exact JSON field names can still be refined during implementation, but the structure should remain stable and unsurprising.

## Error model

The informal CLI should use clear, command-appropriate failures.

### Usage errors

Examples:

- missing required `--module` for tracked-state commands
- invalid `--by` mode
- invalid `--mode` or `--body` values for `present`
- missing positional declaration or node-id arguments

These should return usage-style exit codes and help-oriented messages.

### Not-found errors

Examples:

- targeted `decl` on an untracked declaration
- targeted `ref` on an untracked reference
- `present` on a missing knowledge-base node

These should return not-found-style exit codes/messages.

### Validation errors

Examples:

- invalid bracket/reference node-id text supplied to `ref` or `present`
- malformed knowledge-base node encountered while rendering `present`

These should return validation-style errors when appropriate.

### Important boundary

The informal CLI should not try to repair missing or malformed knowledge-base nodes.
If a node is malformed, the user should fix it through the knowledge-base layer.

## Design decisions for v1

The following decisions are recommended for the first implementation:

1. Use `lake exe aftk informal ...` as the public command shape.
2. Keep the v1 informal CLI primarily query-oriented and read-only.
3. Require `--module` for tracked-state and dependency queries.
4. Reuse the knowledge-base root and resolution policy for presentation commands.
5. Provide top-level commands `status`, `decls`, `decl`, `refs`, `ref`, `deps`, and `present`.
6. Support `deps --by decl|ref` rather than inventing multiple separate dependency command families in v1.
7. Support both text and JSON output from the beginning.
8. Keep per-site occurrence inspection out of the public CLI in v1.
9. Keep knowledge-base content mutation out of the informal CLI.

## Likely future extensions

These are plausible later additions, but they are not required for the first slice:

- targeted dependency lookup commands such as `dep decl <Decl.Name>` or `dep ref <NodeId>`
- more filtering options on `decls`, `refs`, and `deps`
- explicit integration commands combining tracked reference queries with richer presentation in a single output
- validation/diagnostic commands for checking informal-layer consistency assumptions beyond ordinary query failures

## Lean 4 and current-implementation reuse findings

The earlier CLI already provides several useful patterns AFTK should likely reuse:

- manual argument parsing rather than introducing a large CLI framework too early
- repeatable `--module` imports for environment-backed queries
- deterministic sorting at render time
- a `deps --by ...` switch rather than wholly separate implementations for each displayed graph view
- environment import caching keyed by requested modules as an optional optimization

Core Lean adds a few concrete operational findings behind that pattern:

- the environment import path for a CLI tool should use `findSysroot`, `initSearchPath`, `enableInitializersExecution`, and `importModules`
- tracked-state queries specifically need `importModules ... (loadExts := true)` so that persistent environment extensions are available after import
- `withImportModules` is intentionally not appropriate here because it always uses `loadExts := false`

AFTK should preserve the useful existing patterns where they still fit, while removing the old metadata-mutation command family and replacing sidecar-location concepts with knowledge-base-backed references and presentation.

## Open questions for companion docs

This document intentionally leaves nearby details to companion plans:

- Exact tracked-state query semantics belong in `plans/informal/tracking.md`.
- Exact dependency semantics belong in `plans/informal/dependencies.md`.
- Exact presentation payloads and body policies belong in `plans/informal/presentation.md`.
- Module boundaries and CLI-vs-library split belong in `plans/informal/layout.md`.
- CLI integration tests and JSON-shape assertions belong in `plans/informal/testing.md`.

## Summary

AFTK's informal CLI should live at:

```text
lake exe aftk informal ...
```

and should be primarily a query/readback surface over four things:

- declaration-level tracking,
- reverse reference lookup,
- derived dependency views,
- and knowledge-base-backed presentation rendering.

It should require module imports for environment-backed queries, reuse the knowledge-base layer for canonical node resolution, support both text and JSON output from the start, and avoid reintroducing the old sidecar-metadata mutation model of the earlier `informalize` CLI.
