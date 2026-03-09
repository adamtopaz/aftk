# Informal Toolkit Tools Design

## Status

Component design/status document for the informal tool family built on the `aftk informal` CLI.
This file now records the rationale for the tool family that exists in code and the follow-on work that may still be added later.

Authoritative implementation docs live in:

- `docs/toolkit/overview.md`
- `docs/toolkit/library.md`
- `docs/informal/cli.md`

## Component implementation status

- Overall status: Implemented (initial v1), with deferred follow-ons
- Implemented in code: Yes
- Last updated basis: the current informal client/tool implementation in `src/toolkit/informal/client.ts`, `src/toolkit/tools/informal.ts`, the shared runtime/output layers, and `tests/toolkit/**`
- Main deferred follow-ons: any future expansion if the informal CLI surface grows or if higher-level composite helpers become worth adding

The key design questions in this file are now answered by the implemented `informal_*` family.
Historical sections below may still describe pre-implementation expectations; treat them as design rationale only.

## Purpose

This document defines the informal tool family that the toolkit should expose on top of:

```text
lake exe aftk informal ...
```

It is about:

- which informal commands should receive toolkit wrappers in v1
- naming conventions for the informal tool family
- parameter-schema design, especially `modules` and `root` handling
- JSON parsing and normalization policy for the informal CLI’s command-shaped outputs
- the relationship between environment-backed queries and direct presentation queries
- CLI exit-code and error mapping
- and how informal CLI results should be rendered into concise text plus structured details

The goal is to expose AFTK's already implemented informal layer through a practical TypeScript tool surface, while preserving AFTK's key architectural rule that the informal layer is a bridge to the knowledge base rather than a second prose store.

## Design goals

The informal tool family should:

- build directly on the documented informal CLI rather than on hidden environment or file parsing from TypeScript
- expose the current informal CLI surface cleanly, because it is already modest and query-oriented
- remain clearly separate from both:
  - the Lean-facing server-backed `aftk_*` tool family,
  - and the knowledge-base CLI-backed `knowledgebase_*` tool family
- request structured JSON output from the CLI by default and normalize it into the shared toolkit result contract
- make the split between environment-backed queries and knowledge-base-backed presentation explicit
- make `modules` handling clear and ergonomic for environment-backed commands
- keep `present` as a complement to server hover rather than a confusing duplicate of it
- avoid reintroducing any earlier `informalize` sidecar-management API that no longer exists in AFTK
- preserve structured dependency/presentation data for later higher-level agent use

## Scope and non-scope

### In scope

- informal CLI-backed query and presentation tools
- naming conventions for the informal tool family
- parameter schemas for the selected tool set
- JSON parsing and normalization for the informal CLI’s command-shaped success outputs
- mapping informal CLI exit codes and failure JSON into toolkit-visible results
- text rendering rules for status, tracking queries, dependency queries, and direct presentation queries

### Out of scope

- server-backed Lean hover/query/tactic tools
- direct parsing of Lean environments or knowledge-base files from TypeScript
- `pi`-specific registration code
- the old `informalize meta ...` / sidecar-management surface
- redesign of the informal CLI itself
- mutation of knowledge-base content through the informal tool family

Those are covered by lower-layer docs or other toolkit component docs.

## Research basis and design consequences

This tool-family plan is based primarily on the current repository, because the informal layer is already implemented and documented.

### Main-worktree reference points

Primary files studied:

- `../aftk/docs/informalize/README.md`
- `../aftk/docs/agent-playbook.md`
- `../aftk/docs/future/autoformalization-tools.md`

Important observations from the earlier implementation:

- The old Informalize CLI was sidecar-oriented and included commands such as:
  - location queries,
  - metadata inspection/mutation,
  - and sidecar-management operations.
- The earlier playbook used `informal[...]` as a blueprint layer tied to `informal/...` markdown/json files.
- The future-tool roadmap suggests that if informal-layer data is later surfaced through the Lean hub, names like:
  - `aftk_informal_status`
  - `aftk_informal_deps`
  - `aftk_informal_decls`

  would be plausible **hub-aware** additions.

Main consequences for AFTK:

- the old sidecar-management `informalize` CLI is **not** the compatibility target for the AFTK toolkit;
- the AFTK toolkit should wrap AFTK's current `informal` CLI, not resurrect old `informalize meta` or `location` command families;
- and the toolkit should avoid occupying the `aftk_informal_*` namespace in v1, because that namespace is a better fit for possible future hub-backed informal additions.

### Repository reference points

Primary files studied:

- `docs/informal/cli.md`
- `docs/informal/overview.md`
- `plans/informal/cli.md`
- `AFTK/Informal/Cli/Types.lean`
- `AFTK/Informal/Cli/Render.lean`
- `AFTK/Informal/Cli/Parse.lean`
- `AFTK/Informal/Cli/Main.lean`
- `AFTK/Informal/Tracking.lean`
- `AFTK/Informal/Dependencies.lean`
- `AFTK/Informal/Presentation.lean`
- `plans/toolkit/output.md`
- `plans/toolkit/runtime.md`
- `plans/toolkit/knowledgebase-tools.md`

Current AFTK observations:

- The public CLI is:

```text
lake exe aftk informal ...
```

- the AFTK informal CLI is already query-oriented and relatively small.
- The implemented commands are:
  - `status`
  - `decls`
  - `decl`
  - `refs`
  - `ref`
  - `deps`
  - `present`
- The CLI has two real command classes:
  - environment-backed tracking/dependency queries requiring `--module`
  - direct knowledge-base-backed `present` queries that do not require `--module`
- Global options are:
  - `--module <Module.Name>` repeatable
  - `--root <path>`
  - `--format text|json`
  - `--help`
- The CLI’s JSON **success** shape is command-shaped, not envelope-shaped.
  In current implementation, success JSON is centered on a `data` field and then varies by command with additional fields such as:
  - `modules`
  - `target`
  - `mode`
  - `bodyMode`
- The CLI’s JSON **failure** shape includes:
  - `ok: false`
  - `error: { code, message, exitCode }`
  - `command?`
  - `format`
- The CLI’s documented exit codes are:
  - `0` success
  - `1` generic operational/query failure
  - `2` usage error
  - `3` targeted not-found / not-tracked error
  - `4` validation-style failure
  - `5` reserved conflict code, though current commands are read-oriented
- `present` resolves directly through the knowledge base and offers:
  - `mode: compact|rich`
  - `body: none|preview|full`
- `AFTK/Informal/Cli/Main.lean` makes the environment-backed vs presentation-backed split operationally real:
  - environment-backed commands import modules with `loadExts := true`,
  - while `present` bypasses module import and resolves the knowledge-base root directly.
- The current CLI implementation exposes structured result shapes for:
  - status counts
  - declaration entries and reference entries
  - declaration and reference dependency rows/leaves
  - compact presentation summaries
  - rich presentation payloads
- `AFTK/Informal/Cli/Main.lean` currently maps thrown `is not tracked` failures to the structured code `informal.notTracked`, and other environment-backed query failures to `informal.queryFailed`.
- `AFTK/Informal/Tracking.lean` and `AFTK/Informal/Dependencies.lean` sort declaration/reference rows and dependency rows/leaves deterministically before returning them.
- `AFTK/Informal/Presentation.lean` sorts tags, authors, relationship lines, and Lean-ref lines deterministically and currently uses a preview-body policy of 6 lines / 250 characters with explicit `truncated` metadata.
- The informal layer overview explicitly says:
  - the AFTK informal layer does not own a second prose store,
  - canonical prose still lives in the knowledge base,
  - and the server layer already reuses informal presentation for richer hover.

Main consequences for AFTK:

- the toolkit can reasonably wrap the **full current** informal CLI surface in v1 because it is already modest and read-oriented;
- it should expose environment-backed and presentation-backed operations distinctly;
- it should parse command-shaped success JSON explicitly rather than trying to force the informal CLI into the knowledge-base CLI envelope model;
- and it should treat `informal_present` as a direct node-presentation tool that complements, but does not replace, `aftk_get_hover`.

## Core tool-family decisions

The v1 informal-tools design should make the following choices explicit.

### 1. Build on the public informal CLI, not on direct environment or file parsing

The toolkit should invoke:

```text
lake exe aftk informal ...
```

through the shared CLI runner.
It should **not**:

- parse Lean environments directly from TypeScript,
- read persistent extension data from compiled artifacts directly,
- or parse knowledge-base files directly in order to imitate `present`.

That preserves lower-layer ownership of:

- module import semantics,
- tracking-state queries,
- dependency semantics,
- and knowledge-base-backed presentation logic.

### 2. Wrap the full current informal CLI surface in v1

Unlike the knowledge-base CLI, the AFTK informal CLI is already relatively small and entirely query/presentation oriented.
So the initial toolkit surface can and should wrap the full current command set:

- `status`
- `decls`
- `decl`
- `refs`
- `ref`
- `deps`
- `present`

This gives the toolkit immediate practical coverage of the AFTK informal layer without premature mutation design.

### 3. Use an `informal_*` naming convention

The v1 naming convention for this family should be:

- `informal_status`
- `informal_decls`
- `informal_decl`
- `informal_refs`
- `informal_ref`
- `informal_deps`
- `informal_present`

This choice is deliberate:

- it aligns with AFTK's public `informal` naming,
- it avoids the old `informalize` naming from the earlier implementation,
- and it avoids the Lean-family `aftk_*` namespace.

### 4. Do not use `aftk_informal_*` names in v1

The future-tool roadmap already suggests that `aftk_informal_*` would be a natural namespace for **future hub-backed informal tools**.
The current toolkit component here is CLI-backed, not hub-backed.

So the toolkit should reserve that namespace by **not** using it for the current CLI family.

### 5. Keep the environment-backed vs presentation-backed split explicit

The informal CLI already has two natural command classes.
The toolkit should preserve that clarity.

- environment-backed tools require `modules`
- presentation-backed `informal_present` does not require `modules`
- `root` matters primarily for `informal_present`

This keeps the tool contracts cleaner than forcing every tool to accept irrelevant parameters.

### 6. Use `modules: string[]` as the toolkit-facing representation of repeated `--module`

For environment-backed tools, the CLI uses repeated `--module <Module.Name>` flags.
The toolkit should expose this more naturally as:

- `modules: string[]`

Validation rules:

- `modules` is required for environment-backed tools
- `modules` must be non-empty
- module names are passed through in the order provided

The tool layer should not invent more elaborate module-loading abstractions in v1.

### 7. Use CLI JSON mode by default for all toolkit-backed informal calls

The informal tools should call the CLI with:

```text
--format json
```

by default and parse the resulting structured output.
The toolkit should then render its own concise text from the parsed structured result.

This is especially important because the informal CLI’s JSON success shape is command-shaped rather than envelope-shaped.
Using JSON mode deliberately lets the toolkit absorb that lower-layer difference into the shared output contract.

### 8. Keep `root` optional and presentation-specific in v1

The `--root` option matters primarily for `present`.
So the toolkit should expose:

- optional `root` on `informal_present`
- no `root` parameter on the environment-backed query tools in v1

This follows the lower-layer semantics closely and avoids irrelevant parameters on the tracking/dependency tools.

### 9. Keep tool APIs slightly more semantic than raw CLI flags where it improves clarity

The toolkit does not need to mirror every CLI option one-for-one when a small semantic normalization gives a cleaner API.

The clearest example is `informal_present`, which should expose:

- `mode: "compact" | "rich"`
- `body?: "none" | "preview" | "full"`

rather than raw string-flag plumbing.

A good v1 rule is:

- default `mode = "rich"`
- default `body = "preview"` when `mode = "rich"`
- if `mode = "compact"`, `body` should be omitted, and providing it should be treated as a usage error at the toolkit boundary

### 10. Normalize command-shaped success JSON into the shared toolkit output envelope

The informal CLI does not already produce a common `ok/result` success envelope.
The toolkit should therefore normalize each command-shaped success payload into the shared toolkit result contract from `plans/toolkit/output.md`.

That means:

- command and mode metadata move into backend metadata or normalized result context
- the semantic payload becomes the main `details.result`
- CLI failure JSON becomes normalized toolkit errors
- environment-backed module context is preserved structurally

### 11. Treat `informal_present` as a complement to server hover, not a duplicate of it

The server layer already uses the informal layer for richer hover at `informal[...]` sites.
The `informal_present` tool should complement that by providing:

- direct node presentation by reference id,
- without needing a source location or open Lean file.

It should not try to replace or subsume `aftk_get_hover`.

### 12. Do not resurrect old sidecar-management commands in the toolkit surface

The AFTK informal CLI intentionally does **not** include the old `informalize` sidecar-management families such as:

- `locations`
- `location`
- `meta ...`

The toolkit should therefore not invent tool wrappers for those old commands.
If later future layer commands are added, they can be wrapped then.

### 13. The one-shot CLI family does not need a shutdown surface

Like the knowledge-base tool family, the informal tool family uses one-shot CLI commands.
So its dedicated family factory does not need a meaningful `shutdown()` method.

## Initial v1 tool surface

The initial informal toolkit surface should consist of exactly the following tools.

| Tool name | CLI command | Primary role |
| --- | --- | --- |
| `informal_status` | `status` | Show high-level tracking counts for imported modules |
| `informal_decls` | `decls` | List tracked declarations and referenced node ids |
| `informal_decl` | `decl <Decl.Name>` | Show one tracked declaration |
| `informal_refs` | `refs` | List tracked references and their declarations |
| `informal_ref` | `ref <NodeId>` | Show one tracked reference |
| `informal_deps` | `deps` | Show declaration or reference dependency views |
| `informal_present` | `present <NodeId>` | Render direct knowledge-base-backed presentation |

## Shared parameter-schema decisions

The informal tools should reuse a small number of schema fragments.
The exact schema library can still be finalized in code, but the semantic content should follow this design.

### Common modules parameter

All environment-backed informal tools should require:

- `modules: string[]`

Validation rules:

- required
- non-empty
- each entry non-empty

The toolkit should translate this into repeated:

```text
--module <Module.Name>
```

arguments for the CLI.

### `informal_status`

Parameters:

- `modules: string[]`

No additional parameters.

### `informal_decls`

Parameters:

- `modules: string[]`
- `prefix?: string`
- `ref?: string`

These map directly to the lower-layer filters.

### `informal_decl`

Parameters:

- `modules: string[]`
- `declName: string`

### `informal_refs`

Parameters:

- `modules: string[]`
- `prefix?: string`

### `informal_ref`

Parameters:

- `modules: string[]`
- `ref: string`

### `informal_deps`

Parameters:

- `modules: string[]`
- `mode?: "decl" | "ref"`
- `onlyLeaves?: boolean`

Default:

- `mode = "decl"`

### `informal_present`

Parameters:

- `ref: string`
- `root?: string`
- `mode?: "compact" | "rich"`
- `body?: "none" | "preview" | "full"`

Defaults:

- `mode = "rich"`
- `body = "preview"` when `mode = "rich"`

Validation rule:

- `body` should be rejected as a usage error when `mode = "compact"`

## CLI invocation and parsing policy

The informal tool family should use a dedicated CLI bridge beneath the tool definitions.

### Common invocation rule

All tools should invoke the informal CLI with:

```text
lake exe aftk informal --format json ...
```

plus:

- repeated `--module` flags for environment-backed commands
- `--root <path>` for `informal_present` when `root` was provided
- command-specific arguments afterward

### Parse target

The parser should distinguish two broad output classes.

#### Success JSON

Success JSON is command-shaped and should be dispatched by at least:

- `command`
- `mode` for `deps`
- `mode` and optional `bodyMode` for `present`
- presence/shape of the `data` field
- presence of `target` for targeted commands such as `decl`, `ref`, and `present`

#### Failure JSON

Failure JSON is shaped around:

- `ok: false`
- `error: { code, message, exitCode }`
- optional `command`
- `format`

### JSON-shape failures

If the CLI was requested in JSON mode but stdout does not match either the expected success shape or the expected failure shape, that should become a toolkit protocol failure, not a plain CLI-domain failure.

## Normalized result-shape decisions

Within the shared output envelope from `plans/toolkit/output.md`, this family should use:

- `family: "informal"`
- backend kind `"informal_cli"`

The toolkit can use light semantic normalization above raw CLI payloads where that improves clarity.

### Suggested `details.result` shapes

#### `informal_status`

A good normalized shape is:

```ts
{
  modules: string[],
  trackedDeclarations: number,
  trackedReferences: number,
  declarationsWithMultipleReferences: number
}
```

#### `informal_decls`

A good normalized shape is:

```ts
{
  modules: string[],
  filters: { prefix?: string, ref?: string },
  entries: Array<{
    declName: string,
    refCount: number,
    refs: string[]
  }>,
  count: number
}
```

#### `informal_decl`

A good normalized shape is:

```ts
{
  modules: string[],
  target: string,
  entry: {
    declName: string,
    refCount: number,
    refs: string[]
  }
}
```

#### `informal_refs`

A good normalized shape is:

```ts
{
  modules: string[],
  filters: { prefix?: string },
  entries: Array<{
    ref: string,
    declCount: number,
    declNames: string[]
  }>,
  count: number
}
```

#### `informal_ref`

A good normalized shape is:

```ts
{
  modules: string[],
  target: string,
  entry: {
    ref: string,
    declCount: number,
    declNames: string[]
  }
}
```

#### `informal_deps`

A good normalized shape is:

- for `mode = "decl"`:

```ts
{
  modules: string[],
  mode: "decl",
  onlyLeaves: boolean,
  rows: Array<{
    declName: string,
    dependencies: string[]
  }>,
  leaves: string[]
}
```

- for `mode = "ref"`:

```ts
{
  modules: string[],
  mode: "ref",
  onlyLeaves: boolean,
  rows: Array<{
    ref: string,
    dependencies: string[]
  }>,
  leaves: string[]
}
```

#### `informal_present`

A good normalized shape is:

- compact mode:

```ts
{
  target: string,
  mode: "compact",
  summary: InformalPresentationSummary
}
```

- rich mode:

```ts
{
  target: string,
  mode: "rich",
  bodyMode: "none" | "preview" | "full",
  payload: InformalPresentationPayload
}
```

This preserves the lower-layer semantic structure while making the mode split explicit.

## Per-tool behavior

The following sections settle the intended behavior of each initial informal tool.

### Environment-backed tracking tools

#### `informal_status`

##### Purpose

Show high-level tracking counts for imported modules.

##### Input

- `modules`

##### CLI call

```text
informal status --module ...
```

##### Success details

- normalized success envelope
- `family: "informal"`
- backend metadata like `{ kind: "informal_cli", command: "status", modules, exitCode }`
- normalized status result

##### Success text

Preserve the current lower-layer style in spirit:

```text
Tracked declarations: <n>
Tracked references: <n>
Declarations with multiple references: <n>
```

#### `informal_decls`

##### Purpose

List tracked declarations and the references they use.

##### Input

- `modules`
- optional `prefix`
- optional `ref`

##### CLI call

```text
informal decls --module ... [--prefix ...] [--ref ...]
```

##### Success details

- normalized success envelope
- backend command `decls`
- normalized result with `modules`, `filters`, `entries`, and `count`

##### Success text

Text should start with a count summary such as:

- `Tracked declarations (<count>)`

and then render one bullet per entry in stable order, in the style:

- `- <declName> [<refCount>]: <ref1>, <ref2>, ...`

If there are no entries:

- `Tracked declarations (0)`

#### `informal_decl`

##### Purpose

Show one tracked declaration.

##### Input

- `modules`
- `declName`

##### CLI call

```text
informal decl <Decl.Name> --module ...
```

##### Success details

- normalized success envelope
- backend command `decl`
- normalized result with `modules`, `target`, and `entry`

##### Success text

Preserve the current focused-block style in spirit:

```text
Declaration: <declName>
Reference count: <n>
References: <ref1>, <ref2>, ...
```

### Environment-backed reference tools

#### `informal_refs`

##### Purpose

List tracked references and the declarations that reference them.

##### Input

- `modules`
- optional `prefix`

##### CLI call

```text
informal refs --module ... [--prefix ...]
```

##### Success details

- normalized success envelope
- backend command `refs`
- normalized result with `modules`, `filters`, `entries`, and `count`

##### Success text

Text should start with:

- `Tracked references (<count>)`

and then render one bullet per entry like:

- `- <ref> [<declCount>]: <decl1>, <decl2>, ...`

If there are no entries:

- `Tracked references (0)`

#### `informal_ref`

##### Purpose

Show one tracked reference and the declarations that reference it.

##### Input

- `modules`
- `ref`

##### CLI call

```text
informal ref <NodeId> --module ...
```

##### Success details

- normalized success envelope
- backend command `ref`
- normalized result with `modules`, `target`, and `entry`

##### Success text

Preserve the current focused-block style in spirit:

```text
Reference: <ref>
Declaration count: <n>
Declarations: <decl1>, <decl2>, ...
```

### Dependency-view tool

#### `informal_deps`

##### Purpose

Show declaration or reference dependency views.

##### Input

- `modules`
- optional `mode`
- optional `onlyLeaves`

##### CLI call

```text
informal deps --module ... [--by decl|ref] [--only-leaves]
```

##### Success details

- normalized success envelope
- backend command `deps`
- normalized result with `modules`, `mode`, `onlyLeaves`, `rows`, and `leaves`

The toolkit should preserve the lower-layer meaning here: `deps` is a derived view, not a raw import listing.
In current implementation:

- `decl` mode computes transitive tracked-declaration dependencies from `usedConstants`,
- `ref` mode projects those declaration dependencies back onto tracked references.

##### Success text

Text should preserve the current two-part shape in spirit.

For `mode = "decl"`:

```text
Declaration dependencies (<count>)
- <decl> -> <deps>

Leaves (<leafCount>)
- <leaf>
```

For `mode = "ref"`:

```text
Reference dependencies (<count>)
- <ref> -> <deps>

Leaves (<leafCount>)
- <leaf>
```

The toolkit should preserve explicit empty-leaf wording such as `- (none)` when appropriate.

### Direct presentation tool

#### `informal_present`

##### Purpose

Render direct knowledge-base-backed presentation for one reference id.

##### Input

- `ref`
- optional `root`
- optional `mode`
- optional `body`

##### CLI call

```text
informal present <NodeId> [--root ...] [--mode ...] [--body ...]
```

##### Success details

- normalized success envelope
- backend command `present`
- normalized compact or rich result shape depending on `mode`

##### Success text

For `mode = "compact"`, the text should render a compact summary built from:

- reference id
- title
- optional kind
- optional status
- optional summary

For `mode = "rich"`, the text should render:

- the summary block first
- optional tags/authors sections when present
- optional relationships and Lean refs sections when present
- body according to `bodyMode`

If the body is preview-mode and the structured payload says it was truncated, the text should preserve an explicit truncation indication such as `[truncated]`.
The current lower-layer preview policy is already concrete — 6 lines / 250 characters with structured `truncated` metadata — so the toolkit should preserve that structured fact rather than guessing from the rendered text alone.

The goal is to stay close in spirit to the current lower-layer presentation renderer while still generating toolkit-owned text from structured data.

## Error behavior for informal tools

The informal tool family should use the shared normalized failure envelope from `plans/toolkit/output.md`, with informal-family backend metadata.

### Backend metadata on failure

Failures should identify at least:

- `family: "informal"`
- backend kind `"informal_cli"`
- exact CLI command name
- modules when relevant
- root when relevant
- CLI exit code when available
- exact lower-layer error code string when available, such as `informal.notTracked`

### CLI-domain failure mapping

A good v1 mapping is:

- exit code `2` -> `usage`
- exit code `3` on `decl` / `ref` -> `not_tracked`
- exit code `3` on `present` -> `not_found`
- exit code `3` on other targeted commands -> `not_found`
- exit code `4` -> `validation`
- exit code `1` -> `operational`
- malformed JSON or impossible command shape -> `protocol`

This is slightly more informative than a pure exit-code-only mapping while still preserving the raw code and message.
In particular, the current implementation already distinguishes code strings such as:

- `informal.notTracked`
- `informal.queryFailed`

and the toolkit should preserve those exact lower-layer codes in structured details alongside the normalized category.

### Informal-specific actionable text

When the lower-layer failure is clear, the text renderer should be more actionable than a raw error dump.
Examples of the intended style:

- `At least one module is required for this query.`
- `Declaration is not tracked in the imported modules: <declName>`
- `Reference is not tracked in the imported modules: <ref>`
- `Informal node was not found: <ref>`
- `Informal presentation failed because the underlying knowledge-base data is invalid.`
- `Invalid dependency mode. Use decl or ref.`

The structured details remain the stronger compatibility contract.

## Relationship to adjacent tool families

The informal tool family should sit clearly between the knowledge-base and Lean-facing families.

### Relationship to `knowledgebase_*` tools

- `knowledgebase_*` tools inspect canonical knowledge-base data directly through the knowledge-base CLI
- `informal_*` tools inspect declaration↔reference bridge state and knowledge-base-backed presentation through the informal CLI

So `informal_present` is not a replacement for `knowledgebase_show`.
It is a bridge-oriented presentation query with its own semantics.

### Relationship to `aftk_*` Lean tools

- `aftk_get_hover` and `aftk_get_infoview` are source-location and open-file oriented
- `informal_present` is direct reference-id oriented and does not require an open Lean file or source location
- `informal_decls` / `informal_refs` / `informal_deps` expose project-level bridge state that the Lean hub does not currently expose directly

That complementarity should remain explicit.

## Factory API decisions

The informal tool family should have a dedicated factory rather than existing only inside an aggregate bundle.

### Canonical dedicated factory

The canonical implementation surface for this component should be something like:

```ts
createInformalTools(options?)
```

returning conceptually:

```ts
{
  tools
}
```

Because this family uses only one-shot CLI commands, it does not need a meaningful shutdown method.

### Client/tool boundary

The dedicated tool factory should sit above a reusable CLI bridge/client layer for:

```text
lake exe aftk informal ...
```

The tool layer should not construct raw argument lists ad hoc inside every tool definition.

## Recommended module responsibilities

Within the layout settled in `plans/toolkit/layout.md`, the informal family should likely be refined as follows.

### `src/toolkit/informal/client.ts`

This module should own:

- command builders for the selected informal CLI commands
- parsing of command-shaped success JSON
- parsing of informal CLI failure JSON
- informal-specific exit-code handling
- typed result shapes for the selected command wrappers

It should depend on:

- `src/toolkit/runtime/cli.ts`
- shared runtime error types

It should not depend on tool-description or host-specific APIs.

### `src/toolkit/tools/informal.ts`

This module should own:

- informal tool parameter schemas
- tool descriptions and labels
- family-specific text renderers
- the informal tools factory
- mapping client results into the shared output envelope

It should not own:

- raw subprocess execution
- generic output-envelope types
- `pi` registration

## Boundaries and anti-patterns

The informal tool family should explicitly avoid the following mistakes.

### 1. No direct parsing of Lean environments or knowledge-base files from TypeScript

Use the lower-layer CLI boundary AFTK already defines.

### 2. No reuse of the Lean-family `aftk_*` namespace for CLI-backed informal tools

That namespace already means the server-backed Lean family.

### 3. No reuse of the old `informalize_*` naming from the earlier implementation

AFTK public layer is `informal`, not `informalize`.

### 4. No resurrection of old sidecar-management commands that do not exist in AFTK CLI

Do not invent wrappers for `locations`, `location`, or `meta ...` in this component.

### 5. No dependence on lower-layer text output as the main machine contract

Always prefer JSON mode and structured parsing by default.

### 6. No forcing `root` onto every environment-backed command when the lower layer does not need it

Keep the split between `modules` and `root` explicit.

### 7. No confusion between `informal_present` and `aftk_get_hover`

They solve related but distinct problems.

## Initial implementation checklist for this informal tool design

Before the informal tool family can be considered in place, AFTK should reach at least this baseline:

- a reusable informal CLI bridge exists in TypeScript
- the full current informal CLI surface is wrapped
- environment-backed tools require non-empty `modules`
- `informal_present` exposes `mode` and `body` cleanly, with the compact/body validation rule
- all informal tools invoke the CLI in JSON mode by default
- command-shaped success JSON is parsed and normalized reliably
- failure JSON and exit codes are mapped into the shared toolkit error model
- tool names use the chosen `informal_*` naming convention
- all results use the shared toolkit output envelope with `family: "informal"`

## Summary

AFTK already has a compact, query-oriented informal CLI.
That makes the toolkit’s job relatively straightforward: expose the full current informal surface through a clean TypeScript tool family built on:

- one-shot CLI calls,
- explicit `modules` handling for environment-backed queries,
- optional `root` handling for direct presentation,
- parsing of command-shaped success JSON,
- normalized success/failure details,
- and concise, agent-friendly text rendering.

The resulting v1 informal tool family should use:

- `informal_*` names,
- not the Lean-family `aftk_*` names,
- and not the old `informalize` naming.

It should preserve AFTK's actual semantics:

- project-level declaration/reference/dependency queries from imported modules,
- direct knowledge-base-backed node presentation by reference id,
- and no second prose store or sidecar-management API.

That gives the AFTK toolkit a coherent informal-layer surface that complements both the knowledge-base tools and the Lean-facing server tools without blurring their boundaries.
