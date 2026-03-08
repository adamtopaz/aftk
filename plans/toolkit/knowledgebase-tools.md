# Knowledge-Base Toolkit Tools Design

## Status

Component plan and implementation-status document for the knowledge-base tool family built on the rewrite knowledge-base CLI.
This document refines the overall toolkit-layer plan in `plans/toolkit.md` and works together with `plans/toolkit/layout.md`, `plans/toolkit/runtime.md`, `plans/toolkit/server-client.md`, `plans/toolkit/lean-tools.md`, `plans/toolkit/informal-tools.md`, `plans/toolkit/pi-integration.md`, `plans/toolkit/output.md`, and `plans/toolkit/testing.md`.

## Component implementation status

- Overall status: Not implemented
- Implemented in code: No
- Last updated basis: research against the rewrite knowledge-base CLI docs in `docs/knowledgebase/cli.md`, `docs/knowledgebase/overview.md`, and `plans/knowledgebase/cli.md`, plus the toolkit output/runtime plans and the current CLI implementation behavior in `AFTK/KnowledgeBase/Cli/*`, `AFTK/KnowledgeBase/PathLayout.lean`, and `AFTK/KnowledgeBase/Validation.lean`

## Purpose

This document defines the knowledge-base tool family that the toolkit should expose on top of:

```text
lake exe aftk knowledgebase ...
```

It is about:

- which knowledge-base commands should receive toolkit wrappers first
- naming conventions for the knowledge-base tool family
- parameter schema design
- JSON parsing and normalization policy
- mutation-vs-query boundaries
- validation/report semantics
- CLI exit-code and error mapping
- and how knowledge-base CLI results should be rendered into concise text plus structured details

The goal is to expose the rewrite’s already implemented knowledge-base layer through a practical TypeScript tool surface, without bypassing the CLI boundary or mirroring every single command prematurely.

## Design goals

The knowledge-base tool family should:

- build directly on the documented knowledge-base CLI rather than on hidden file parsing
- start with a selected high-value read/query/report surface rather than mirroring the entire mutation surface immediately
- preserve the knowledge-base layer’s public naming discipline by preferring `knowledgebase` over `kb`
- remain clearly separate from the Lean-facing `aftk_*` tool family
- request structured JSON output from the CLI by default and normalize it into the shared toolkit result contract
- preserve structured knowledge-base results and validation reports for higher-level code
- expose a practical set of agent-facing discovery tools:
  - status/probe
  - list/show
  - search
  - relationship traversal
  - validation/reporting
- make root selection explicit without forcing callers to pass it in the common case
- keep mutation commands deferred until the CLI bridge, output model, and testing story are stable

## Scope and non-scope

### In scope

- knowledge-base CLI-backed query/reporting tools
- naming conventions for the knowledge-base tool family
- parameter schemas for the selected first tool set
- JSON parsing and envelope normalization for CLI responses
- mapping knowledge-base CLI exit codes and error codes into toolkit-visible results
- text rendering rules for the selected knowledge-base tools
- treatment of validation reports and their special exit-code behavior

### Out of scope

- direct parsing of canonical `knowledgebase/` files from TypeScript
- server-backed Lean tools
- informal CLI-backed tools
- host-specific `pi` registration
- the full mutation/admin command surface of the knowledge-base CLI in v1
- redesign of the knowledge-base CLI itself

Those are covered by lower-layer docs or other toolkit component docs.

## Research basis and design consequences

This tool-family plan is based primarily on the current rewrite worktree, because the rewrite knowledge-base layer is already implemented and documented.

### Main-worktree reference points

Primary files studied:

- `/home/dev/aftk/docs/aftk/README.md`
- `/home/dev/aftk/docs/agent-playbook.md`
- `/home/dev/aftk/docs/future/autoformalization-tools.md`

Important observations from the main worktree:

- The main worktree already treats the knowledge-base CLI as a distinct lower-layer interface alongside the Lean-facing hub tools.
- The main worktree does **not** currently ship a dedicated TypeScript knowledge-base tool family analogous to the `aftk_*` hub tools.
- The playbook and combined AFTK docs show that agents are already expected to combine:
  - repository-local knowledge-base operations,
  - informal/blueprint operations,
  - and Lean-facing hub tools.
- The future roadmap emphasizes higher-level workflow integration above the current CLI surfaces rather than replacing those lower-layer boundaries.

Main consequences for the rewrite:

- there is no direct existing TypeScript knowledge-base tool family to preserve for backward compatibility;
- the rewrite therefore has more freedom to design a good first toolkit surface for knowledge-base operations;
- but that freedom should be used conservatively, by exposing the implemented CLI thoughtfully rather than inventing a parallel knowledge-base API detached from the lower layer.

### Rewrite-worktree reference points

Primary files studied:

- `docs/knowledgebase/cli.md`
- `docs/knowledgebase/overview.md`
- `plans/knowledgebase/cli.md`
- `plans/knowledgebase/validation.md`
- `plans/knowledgebase/search.md`
- `AFTK/KnowledgeBase/Cli/Render.lean`
- `AFTK/KnowledgeBase/Cli/Main.lean`
- `AFTK/KnowledgeBase/Cli/Types.lean`
- `AFTK/KnowledgeBase/PathLayout.lean`
- `AFTK/KnowledgeBase/Validation.lean`
- `AFTK/KnowledgeBase/Search.lean`
- `plans/toolkit/output.md`
- `plans/toolkit/runtime.md`

Important rewrite observations:

- The public CLI is:

```text
lake exe aftk knowledgebase ...
```

- The knowledge-base docs explicitly prefer `knowledgebase` over the abbreviation `kb` for the public surface.
- Global CLI options are:
  - `--root <path>`
  - `--format text|json`
  - `--help`
- The implemented command families include:
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
- The CLI has a stable JSON success envelope:
  - `command`
  - `root`
  - `ok: true`
  - `result`
  - `warnings`
- In current implementation, the `command` field is an exact dot-separated lower-layer identifier such as:
  - `metadata.validate`
  - `validate.storage`
  - `search.text`
  - `relationships.related`
- The raw `result` payload is still command-specific rather than fully uniform, for example:
  - `list` returns `{ nodes: [...] }`
  - `metadata show` returns `{ metadata: ... }`
  - `paths` returns `{ id, paths }`
  - outgoing/incoming relationships return `{ id, relationships }`
- The CLI has a stable JSON failure envelope:
  - `command`
  - `root`
  - `ok: false`
  - `error: { code, message }`
  - `warnings`
- Exit codes are meaningful and documented:
  - `0` success
  - `1` generic operational failure
  - `2` usage error
  - `3` not found
  - `4` validation failure
  - `5` conflict
- Validation commands have a special behavior:
  - they return a structured validation report as a **successful command result**,
  - but the CLI exit code becomes `4` when `report.ok = false`.
- `status` is intentionally probe-like and can describe an uninitialized root.
- In current implementation, `status` is the only command that bypasses `requireInitialized`; the rest of the command family resolves an initialized root first.
- `AFTK/KnowledgeBase/PathLayout.resolveRootPath` resolves relative roots against the command process working directory, so the toolkit runtime’s chosen child `cwd` determines the lower layer’s default `knowledgebase/` root when `--root` is omitted.
- The current mutation commands also already reveal one useful fact for later toolkit phases:
  - `body set` and `metadata replace` return the updated stored-node view rather than only an acknowledgment.
- The current knowledge-base layer already exposes stable structured types for:
  - status info
  - stored nodes
  - metadata
  - paths
  - search hits/results
  - relationship views
  - validation reports

Main consequences for the rewrite:

- the toolkit should default to `--format json` and normalize the CLI envelope into the shared toolkit result contract;
- it should preserve the special semantic status of validation reports rather than flattening them into generic tool failures;
- it should start with the CLI’s read/query/report surface, because that is already broad and useful;
- and it should adopt a naming convention that stays consistent with the knowledge-base layer’s public choice of `knowledgebase` rather than `kb`.

## Core tool-family decisions

The v1 knowledge-base tools design should make the following choices explicit.

### 1. Build on the public CLI, not on direct filesystem parsing

The toolkit should invoke:

```text
lake exe aftk knowledgebase ...
```

through the shared CLI runner.
It should **not** parse canonical `knowledgebase/` files directly from TypeScript.

This preserves lower-layer ownership of:

- root resolution semantics
- node-id parsing/validation
- search semantics
- validation semantics
- storage mutation rules

### 2. Start with a selected query/reporting surface, not the full mutation surface

The initial knowledge-base toolkit family should focus on commands that are already most valuable for agent inspection and planning:

- `status`
- `list`
- `show`
- `search text`
- `search tag`
- `relationships ...`
- validation/reporting commands

The following mutation/admin commands should be intentionally deferred in v1:

- `init`
- `create`
- `rename`
- `delete`
- `body set`
- `metadata replace`

Reasoning:

- the top-level toolkit plan already prioritizes read/query/report first;
- mutation wrappers will need stronger fixture discipline and more nuanced testing;
- and the rewrite does not need to block useful agent workflows on immediate mutation coverage.

### 3. Use a naming convention distinct from the Lean-facing `aftk_*` family

The Lean-facing server-backed family already owns the `aftk_*` namespace in practice.
The knowledge-base tools should therefore use a different naming convention.

The v1 naming convention for this family should be:

- `knowledgebase_status`
- `knowledgebase_list`
- `knowledgebase_show`
- `knowledgebase_search_text`
- `knowledgebase_search_tag`
- `knowledgebase_relationships`
- `knowledgebase_validate_storage`
- `knowledgebase_validate_node`
- `knowledgebase_validate_metadata`
- `knowledgebase_validate_all`

This choice is deliberate for two reasons:

1. it avoids colliding semantically with the established Lean-facing `aftk_*` family; and
2. it follows the knowledge-base layer’s explicit public preference for `knowledgebase` over `kb`.

### 4. Prefer full `knowledgebase` spelling over `kb` in the toolkit surface

The knowledge-base layer has already made a public naming decision:

- use `knowledgebase`, not `kb`, in the public CLI surface.

The toolkit should align with that unless a later design explicitly revisits the naming policy across the whole toolkit.

So v1 should prefer:

- `knowledgebase_show`

not:

- `kb_show`
- `aftk_kb_show`

### 5. Use CLI JSON mode by default for all toolkit-backed knowledge-base calls

The knowledge-base tools should call the CLI with:

```text
--format json
```

by default and parse the resulting envelope.
The toolkit should render its own concise text from the parsed structured result.

This keeps:

- machine-readable data authoritative,
- toolkit text consistent with other tool families,
- and lower-layer text formatting free to evolve independently.

### 6. Expose `root` as an optional explicit parameter on every knowledge-base tool

Every knowledge-base tool should accept an optional `root` parameter.
If provided, it should be forwarded as:

```text
--root <path>
```

If omitted, the CLI should use its lower-layer default.
Because the toolkit runtime executes commands from the resolved project root, that lower-layer default will ordinarily mean:

```text
<projectRoot>/knowledgebase
```

This gives callers explicit override power without forcing them to pass `root` constantly.

### 7. Keep tool APIs slightly more semantic than raw CLI flags where that improves clarity

The toolkit does not need to mirror every CLI flag one-for-one when a small semantic normalization makes the tool easier to use.

The clearest example is `knowledgebase_show`, which should use an enum-like `view` parameter such as:

- `combined`
- `body`
- `metadata`
- `paths`

rather than exposing three separate boolean flags.

This still maps cleanly onto the CLI, but it gives a simpler tool contract.

### 8. Preserve knowledge-base CLI structured results, but normalize the envelope

The toolkit should not expose the raw CLI envelope as its stable public details contract.
Instead it should normalize that envelope into the shared toolkit result contract from `plans/toolkit/output.md`.

That means:

- `command` and `root` move into backend metadata and diagnostics where appropriate
- `warnings` move into the normalized warnings array
- the semantic CLI `result` becomes the main `details.result` payload
- CLI failure envelopes become normalized toolkit errors

### 9. Treat validation reports as semantic results, not generic tool failures

The knowledge-base CLI has a special and useful validation behavior:

- validation commands return a structured `ValidationReport`
- exit code `4` indicates `report.ok = false`
- but the command still produced a meaningful report result

The toolkit should preserve that meaning.

So for the knowledge-base validation tools:

- a successfully parsed validation report should normally become a **successful toolkit result**, even if `report.ok = false`
- the structured report should be preserved in `details.result`
- the text should clearly say whether validation passed or found issues
- backend metadata should preserve the CLI exit code so callers can still observe the lower-layer convention

This is an intentional exception to the simple “non-zero exit means tool failure” rule.
It matches the lower-layer semantics better and is much more useful for agents.

### 10. Keep other non-zero CLI outcomes as real tool failures

Outside the validation-report case above, non-zero CLI outcomes should normally become toolkit failures.
That includes cases such as:

- usage errors
- not-found errors
- conflict errors
- generic operational failures
- malformed-root failures

These should use the shared normalized failure envelope and preserve:

- CLI exit code
- CLI error code string when present
- CLI message

### 11. Keep the family focused on node-centric inspection and discovery

The knowledge-base toolkit family exists to expose node-centric inspection and discovery operations.
It should not try to become:

- a full prose editor,
- a hidden second search engine,
- or a bypass around the knowledge-base layer’s own CLI rules.

### 12. Do not invent toolkit-only filters where the CLI does not already expose them

Where the CLI already exposes a natural filter or parameter, the toolkit should preserve it.
Where the CLI does **not** expose a parameter, the toolkit should be cautious about inventing one.

So for v1:

- preserve existing CLI filters such as `--prefix`, `--kind`, `--status`, `--tag`, and `--limit` where they already exist
- do not add a toolkit-only `limit` to commands like `list` that currently have no lower-layer limit option
- rely on shared output truncation for display bounding where needed

### 13. The one-shot CLI family does not need a shutdown surface

Unlike the managed Lean hub client, the knowledge-base tool family only uses one-shot CLI commands.
So its dedicated family factory should **not** need a meaningful `shutdown()` surface.

If an aggregate toolset wants a uniform cleanup interface later, it can provide a no-op wrapper.
But the canonical knowledge-base tool-family factory itself should not pretend to manage long-lived state that it does not own.

## Initial v1 tool surface

The initial knowledge-base toolkit surface should consist of the following tools.

| Tool name | CLI command | Primary role |
| --- | --- | --- |
| `knowledgebase_status` | `status` | Probe root status, including uninitialized roots |
| `knowledgebase_list` | `list` | List nodes with lightweight metadata filters |
| `knowledgebase_show` | `show` | Inspect one node, body, metadata, or paths |
| `knowledgebase_search_text` | `search text` | Search body/title/summary text |
| `knowledgebase_search_tag` | `search tag` | Search by exact tag |
| `knowledgebase_relationships` | `relationships outgoing|incoming|related` | Traverse explicit relationships for one node |
| `knowledgebase_validate_storage` | `validate storage` | Validate root/storage structure |
| `knowledgebase_validate_node` | `validate node <id>` | Validate one full node pair |
| `knowledgebase_validate_metadata` | `metadata validate <id>` | Validate one node’s metadata only |
| `knowledgebase_validate_all` | `validate all` | Run whole-root validation |

This surface is intentionally read/query/report-heavy and deliberately omits mutation commands in v1.

## Deferred commands and why they are deferred

The following lower-layer commands are intentionally deferred from the initial toolkit family.

### `init`

This is a setup/admin command rather than an everyday agent inspection tool.
It can remain CLI-only initially.

### `create`, `rename`, `delete`

These are real content mutations.
They should wait until the mutation-test strategy and rollback/fixture story are explicit in `plans/toolkit/testing.md`.

### `body show`, `metadata show`, `paths`

These are not fundamentally deferred as capabilities.
Instead, they are folded into `knowledgebase_show` via its `view` parameter.

### `body set`, `metadata replace`

These are content-mutation operations and should likewise wait for the later mutation phase.

## Shared parameter-schema decisions

The knowledge-base tools should reuse a small number of shared schema fragments.
The exact schema library can still be finalized in code, but the semantic content should follow this design.

### Common optional root parameter

All knowledge-base tools should support:

- `root?: string`

Meaning:

- when present, forward as `--root <path>`
- when absent, let the CLI use its lower-layer default

The tool layer should not reinterpret the root path beyond ordinary string passing.

### `knowledgebase_status`

Parameters:

- `root?: string`

No additional parameters.

### `knowledgebase_list`

Parameters:

- `root?: string`
- `prefix?: string`
- `kind?: string`
- `status?: string`
- `tag?: string`

`kind` should be restricted to the currently documented node kinds:

- `note`
- `definition`
- `theorem`
- `proofSketch`
- `example`
- `explanation`
- `concept`
- `documentation`

`status` should be restricted to the currently documented node statuses:

- `draft`
- `active`
- `deprecated`
- `archived`

These filters should be optional and combined conjunctively, matching the lower-layer CLI.

### `knowledgebase_show`

Parameters:

- `root?: string`
- `id: string`
- `view?: "combined" | "body" | "metadata" | "paths"`

Default:

- `view = "combined"`

Mapping to CLI:

- `combined` -> `show <id>`
- `body` -> `show <id> --body`
- `metadata` -> `show <id> --metadata`
- `paths` -> `show <id> --paths`

### `knowledgebase_search_text`

Parameters:

- `root?: string`
- `query: string`
- `limit?: integer >= 1`

The tool should preserve the CLI’s existing `--limit` when provided.

### `knowledgebase_search_tag`

Parameters:

- `root?: string`
- `tag: string`
- `limit?: integer >= 1`

### `knowledgebase_relationships`

Parameters:

- `root?: string`
- `id: string`
- `mode: "outgoing" | "incoming" | "related"`

This single tool is justified because:

- all three lower-layer commands require the same essential input,
- they are one conceptual operation family,
- and the mode enum is simple and explicit.

### `knowledgebase_validate_storage`

Parameters:

- `root?: string`

### `knowledgebase_validate_node`

Parameters:

- `root?: string`
- `id: string`

### `knowledgebase_validate_metadata`

Parameters:

- `root?: string`
- `id: string`

### `knowledgebase_validate_all`

Parameters:

- `root?: string`

## CLI invocation and parsing policy

The knowledge-base tool family should use a shared CLI bridge beneath the tool definitions.

### Common invocation rule

All tools should invoke the knowledge-base CLI with:

```text
lake exe aftk knowledgebase --format json ...
```

plus:

- `--root <path>` when `root` was provided
- the command-specific arguments afterward

### Parse target

The first parse target should always be the stable knowledge-base JSON envelope.
A successful parse should inspect at least:

- `command`
- `root`
- `ok`
- `result` or `error`
- `warnings`

The parser should preserve the exact raw CLI `command` string from the envelope, including current dot-separated values such as `validate.storage` and `relationships.related`, and surface that value in backend metadata.

### JSON-shape failures

If the command was requested in JSON mode but stdout is not parseable as the expected knowledge-base envelope, that should become a toolkit protocol failure, not a plain CLI-domain failure.

### Warning preservation

Even though the current CLI often emits `warnings: []`, the toolkit should preserve warnings structurally because the lower-layer contract already reserves that field.

## Normalized result-shape decisions

Within the shared output envelope from `plans/toolkit/output.md`, this family should use:

- `family: "knowledgebase"`
- backend kind `"knowledgebase_cli"`

The knowledge-base tools can use modest result normalization above raw CLI command results when that makes the family easier to consume.

### Suggested `details.result` shapes

The following normalized semantic result shapes are appropriate for the initial tool set.

#### `knowledgebase_status`

`details.result` should preserve the lower-layer status object directly.
That object already has a small, meaningful structured shape.

#### `knowledgebase_list`

A good normalized shape is:

```ts
{
  items: NodeMetadata[],
  count: number,
  filters: { prefix?, kind?, status?, tag? }
}
```

This is slightly more descriptive than a bare array while preserving the lower-layer node metadata payloads unchanged.

#### `knowledgebase_show`

A good normalized shape is:

```ts
{
  id: string,
  view: "combined" | "body" | "metadata" | "paths",
  value: StoredNode | string | NodeMetadata | NodePaths
}
```

This keeps the semantics explicit without losing the underlying payload.

#### `knowledgebase_search_text`

A good normalized shape is:

```ts
{
  query: string,
  limit?: number,
  hits: SearchHit[],
  count: number
}
```

#### `knowledgebase_search_tag`

A good normalized shape is:

```ts
{
  tag: string,
  limit?: number,
  hits: SearchHit[],
  count: number
}
```

#### `knowledgebase_relationships`

A good normalized shape is:

- for `mode = "outgoing"`:

```ts
{
  id: string,
  mode: "outgoing",
  relationships: Relationship[]
}
```

- for `mode = "incoming"`:

```ts
{
  id: string,
  mode: "incoming",
  relationships: IncomingRelationship[]
}
```

- for `mode = "related"`:

```ts
{
  id: string,
  mode: "related",
  outgoing: Relationship[],
  incoming: IncomingRelationship[]
}
```

### Validation tools

A good normalized shape is:

```ts
{
  scope: "storage" | "node" | "metadata" | "all",
  targetId?: string,
  report: ValidationReport
}
```

This makes the validation target explicit while preserving the lower-layer report payload unchanged.

## Per-tool behavior

The following sections settle the intended behavior of each initial knowledge-base tool.

### Probe and inspection tools

#### `knowledgebase_status`

##### Purpose

Probe the resolved knowledge-base root and report initialization status.

##### Input

- optional `root`

##### CLI call

```text
knowledgebase status
```

with `--root` if provided.

##### Success details

- normalized success envelope
- `family: "knowledgebase"`
- `backend: { kind: "knowledgebase_cli", command: "status", root?, exitCode }`
- `result`: status info object

##### Success text

Text should summarize:

- resolved root
- whether initialized
- node count

A good style is:

```text
Knowledge base root: <root>
Initialized: yes|no
Nodes: <count>
```

If not initialized, text should say so plainly rather than treating it as a tool failure.

#### `knowledgebase_list`

##### Purpose

List nodes with lightweight metadata filters.

##### Input

- optional `root`
- optional `prefix`
- optional `kind`
- optional `status`
- optional `tag`

##### CLI call

```text
knowledgebase list [--prefix ...] [--kind ...] [--status ...] [--tag ...]
```

##### Success details

- normalized success envelope
- backend command `list`
- normalized `result` with `items`, `count`, and applied filters

##### Success text

Text should start with a short count summary and then list rows in stable order.
A good v1 style is:

```text
Nodes: <count>
- <id> | <kind> | <status> | <title>
```

If no nodes match, text should say:

- `No nodes matched the requested filters.`

#### `knowledgebase_show`

##### Purpose

Inspect one node or one view of that node.

##### Input

- optional `root`
- `id`
- optional `view`

##### CLI call

```text
knowledgebase show <id>
knowledgebase show <id> --body
knowledgebase show <id> --metadata
knowledgebase show <id> --paths
```

depending on `view`.

##### Success details

- normalized success envelope
- backend command `show`
- normalized `result` containing `id`, `view`, and `value`

##### Success text

Text should depend on `view`.

- `combined`:
  - concise metadata summary,
  - paths summary,
  - and body preview/full text according to the lower-layer combined result
- `body`:
  - body text only
- `metadata`:
  - compact metadata summary rather than raw JSON by default
- `paths`:
  - canonical markdown and metadata paths

The text should remain concise and readable.
The structured details remain the main way to inspect the full payload programmatically.

### Search and discovery tools

#### `knowledgebase_search_text`

##### Purpose

Search body/title/summary text using the knowledge-base layer’s current text-search semantics.

##### Input

- optional `root`
- `query`
- optional `limit`

##### CLI call

```text
knowledgebase search text <query> [--limit <n>]
```

##### Success details

- normalized success envelope
- backend command `search.text`
- normalized result with `query`, `limit?`, `hits`, and `count`

##### Success text

Text should start with a short summary like:

- `Text search hits: <count>`

and then show one stable block per hit, including:

- node id
- title if present
- short snippet if present

If there are no hits:

- `No text-search hits.`

#### `knowledgebase_search_tag`

##### Purpose

Search by exact tag.

##### Input

- optional `root`
- `tag`
- optional `limit`

##### CLI call

```text
knowledgebase search tag <tag> [--limit <n>]
```

##### Success details

- normalized success envelope
- backend command `search.tag`
- normalized result with `tag`, `limit?`, `hits`, and `count`

##### Success text

Text should start with a summary like:

- `Tag search hits: <count>`

and then render each hit with id plus optional title/summary.

If there are no hits:

- `No tag-search hits.`

#### `knowledgebase_relationships`

##### Purpose

Inspect outgoing, incoming, or combined relationships for one node.

##### Input

- optional `root`
- `id`
- `mode`

##### CLI call

```text
knowledgebase relationships outgoing <id>
knowledgebase relationships incoming <id>
knowledgebase relationships related <id>
```

depending on `mode`.

##### Success details

- normalized success envelope
- backend command `relationships.<mode>` using the exact lower-layer mode-specific value:
  - `relationships.outgoing`
  - `relationships.incoming`
  - `relationships.related`
- normalized result whose exact shape depends on `mode`

##### Success text

Preferred rendering rules:

- `outgoing`: show count plus one line/block per relationship with kind and target
- `incoming`: show count plus one line/block per source relationship
- `related`: show separate `Outgoing` and `Incoming` sections

If the selected relationship set is empty, use explicit empty wording such as:

- `No outgoing relationships.`
- `No incoming relationships.`

### Validation and reporting tools

#### Validation tool principle

All validation tools should preserve the structured validation report as the core semantic result.
They should not turn “report found errors” into a generic opaque failure.

#### `knowledgebase_validate_storage`

##### Purpose

Validate root/storage structure.

##### Input

- optional `root`

##### CLI call

```text
knowledgebase validate storage
```

##### Success details

- normalized success envelope
- backend command `validate.storage`
- backend exit code preserved, including exit code `4` when `report.ok = false`
- normalized result `{ scope: "storage", report }`

##### Success text

Text should clearly summarize whether validation passed or found issues, for example:

- `Storage validation passed.`
- `Storage validation found 3 issue(s), including 1 error(s).`

It should then include a short issue summary or first issues as space allows.

#### `knowledgebase_validate_node`

##### Purpose

Validate one full node pair.

##### Input

- optional `root`
- `id`

##### CLI call

```text
knowledgebase validate node <id>
```

##### Success details

- normalized success envelope
- backend command `validate.node`
- backend exit code preserved
- normalized result `{ scope: "node", targetId: <id>, report }`

##### Success text

Text should say whether validation passed and identify the target node id.

#### `knowledgebase_validate_metadata`

##### Purpose

Validate one node’s metadata only.

##### Input

- optional `root`
- `id`

##### CLI call

```text
knowledgebase metadata validate <id>
```

##### Success details

- normalized success envelope
- backend command `metadata.validate`
- backend exit code preserved
- normalized result `{ scope: "metadata", targetId: <id>, report }`

##### Success text

Text should say whether metadata validation passed and identify the target node id.

#### `knowledgebase_validate_all`

##### Purpose

Run whole-root validation.

##### Input

- optional `root`

##### CLI call

```text
knowledgebase validate all
```

##### Success details

- normalized success envelope
- backend command `validate.all`
- backend exit code preserved
- normalized result `{ scope: "all", report }`

##### Success text

Text should summarize the number of issues and errors/warnings found.

## Validation-specific exit-code policy

Because the knowledge-base CLI treats validation specially, the toolkit should also document a special rule here.

### Rule

For the four validation/reporting tools in this component:

- exit code `0` with a valid success envelope means validation produced a report and `report.ok = true`
- exit code `4` with a valid success envelope means validation produced a report and `report.ok = false`
- both cases should become a **successful toolkit result** carrying the report

### Failure cases

Validation tools should still become toolkit failures when the CLI did **not** produce a valid semantic report, for example:

- usage error
- targeted node not found before validation could run
- malformed JSON envelope
- runtime spawn failure

That distinction is important and should be preserved in code and tests.

## Error behavior for knowledge-base tools

The knowledge-base tool family should use the shared normalized failure envelope from `plans/toolkit/output.md`, with knowledge-base-family backend metadata.

### Backend metadata on failure

Failures should identify at least:

- `family: "knowledgebase"`
- backend kind `"knowledgebase_cli"`
- exact raw CLI command name from the envelope, including current dot-separated values such as `validate.storage`
- CLI exit code when available
- resolved root when available

### CLI-domain failure mapping

For non-validation failure envelopes or non-zero exits, the knowledge-base tools should preserve:

- CLI exit code
- CLI error code string, such as `node.notFound`
- CLI message

and map them into normalized categories roughly as follows:

- exit code `2` -> `usage`
- exit code `3` -> `not_found`
- exit code `4` -> `validation` when it is a real CLI failure rather than a successful validation report
- exit code `5` -> `conflict`
- exit code `1` -> `operational`

### Knowledge-base specific actionable text

When CLI error codes/messages make the situation clear, the text renderer should be more actionable than a raw dump.
Examples of the intended style:

- `Node not found: <id>`
- `Knowledge base root is not initialized.`
- `Validation failed before a report could be produced.`
- `Knowledge base command usage error.`

The structured details still remain the stronger compatibility contract.

## Factory API decisions

The knowledge-base tool family should have a dedicated factory rather than existing only inside an aggregate bundle.

### Canonical dedicated factory

The canonical implementation surface for this component should be something like:

```ts
createKnowledgeBaseTools(options?)
```

returning conceptually:

```ts
{
  tools
}
```

Because this family only uses one-shot CLI commands, it does not need a meaningful shutdown method.

### Client/tool boundary

The dedicated tool factory should sit above a reusable CLI bridge/client layer for:

```text
lake exe aftk knowledgebase ...
```

The tool layer should not construct raw argument lists ad hoc inside every tool definition.

## Recommended module responsibilities

Within the layout settled in `plans/toolkit/layout.md`, the knowledge-base family should likely be refined as follows.

### `src/toolkit/knowledgebase/client.ts`

This module should own:

- command builders for the selected knowledge-base CLI commands
- JSON-envelope parsing and normalization
- knowledge-base-specific exit-code handling
- the special validation-report behavior described above
- typed result shapes for the selected command wrappers

It should depend on:

- `src/toolkit/runtime/cli.ts`
- shared runtime error types

It should not depend on tool-description or host-specific APIs.

### `src/toolkit/tools/knowledgebase.ts`

This module should own:

- knowledge-base tool parameter schemas
- tool descriptions and labels
- family-specific text renderers
- the knowledge-base tools factory
- mapping client results into the shared output envelope

It should not own:

- raw subprocess execution
- generic output-envelope types
- `pi` registration

## Boundaries and anti-patterns

The knowledge-base tool family should explicitly avoid the following mistakes.

### 1. No direct parsing of canonical knowledge-base files from TypeScript

Use the CLI boundary the rewrite already defines.

### 2. No premature mirroring of every mutation command

Read/query/report tools first.
Mutation tools later, once testing and semantics are tighter.

### 3. No `kb_*` public tool names in v1

The lower layer has already chosen `knowledgebase` as the public spelling.
The toolkit should follow it.

### 4. No reuse of the Lean-family `aftk_*` namespace for knowledge-base tools

That namespace already means the server-backed Lean tool family.

### 5. No treating validation reports as generic errors just because the exit code is `4`

That would throw away useful semantic data the lower layer intentionally returns.

### 6. No dependence on lower-layer text output as the main machine contract

Always prefer JSON mode and structured parsing by default.

### 7. No toolkit-only filters or rewritten semantics unless explicitly justified

The toolkit should be selective, but it should not quietly invent a second search/query language above the CLI.

## Initial implementation checklist for this knowledge-base tool design

Before the knowledge-base tool family can be considered in place, the rewrite should reach at least this baseline:

- a reusable knowledge-base CLI bridge exists in TypeScript
- the initial selected query/report tool set is implemented
- all knowledge-base tools accept optional `root`
- all knowledge-base tools invoke the CLI in JSON mode by default
- the knowledge-base JSON envelope is parsed and normalized reliably
- validation commands preserve structured reports even when the CLI exit code is `4`
- mutation commands remain intentionally deferred rather than half-implemented
- tool names use the chosen non-`aftk_*`, non-`kb_*` naming convention
- all results use the shared toolkit output envelope with `family: "knowledgebase"`

## Summary

The rewrite already has a substantial knowledge-base CLI.
The toolkit’s job is not to bypass that layer or mirror every command immediately.
Its v1 job is to expose the most useful knowledge-base inspection and discovery operations through a clean TypeScript tool family built on:

- one-shot CLI calls,
- JSON-envelope parsing,
- normalized success/failure details,
- and concise, agent-friendly text rendering.

So the first knowledge-base tool family should be:

- query-first rather than mutation-first,
- named distinctly from the Lean-facing `aftk_*` family,
- aligned with the public `knowledgebase` spelling of the lower layer,
- careful about preserving CLI semantics such as probe-like `status` and report-oriented validation,
- and explicit about structured errors, warnings, root selection, and result normalization.

That gives the rewrite toolkit a practical knowledge-base surface without breaking lower-layer boundaries or overcommitting too early to a much larger mutation API.
