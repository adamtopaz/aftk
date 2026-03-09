# Toolkit Output and Result Contract

## Status

Component design/status document for the cross-tool output contract of the toolkit layer.
This file now records the rationale for the result envelope that exists in code and the follow-on work that may still be added later.

Authoritative implementation docs live in:

- `docs/toolkit/overview.md`
- `docs/toolkit/library.md`
- `docs/toolkit/testing.md`

## Component implementation status

- Overall status: Implemented (initial v1), with deferred follow-ons
- Implemented in code: Yes
- Last updated basis: the shared output implementation in `src/toolkit/output/**`, together with the current tool families and `tests/toolkit/**`
- Main deferred follow-ons: any future richer diagnostics surfacing or result-shape evolution driven by higher-layer needs

The output-contract questions this file was written to settle are now answered by the current toolkit implementation.
Historical sections below may still describe pre-implementation expectations; read them as design rationale only.

## Purpose

This document defines how toolkit-backed tools should present results and failures.
It is about:

- the cross-tool result contract
- the relationship between concise human-facing text and structured machine-facing details
- truncation policy
- stderr and diagnostic handling
- success and error envelopes
- normalization across server-backed and CLI-backed tools
- and what later host adapters such as `pi` should be able to rely on

The goal is to prevent each tool family from inventing its own incompatible return format.
The toolkit should instead have one deliberate output contract that preserves lower-layer semantics while still giving higher layers a consistent interface.

## Design goals

The output layer should:

- make structured details the stronger compatibility contract than free-form text
- still provide concise, useful human-facing text for direct inspection by agents and humans
- normalize differences between:
  - server JSON-RPC results,
  - knowledge-base CLI JSON envelopes,
  - and informal CLI command-shaped JSON
- keep outputs bounded and explicit about truncation
- preserve lower-layer failure information without forcing callers to scrape error strings
- keep runtime/process diagnostics available without dumping them into every success message
- let tool-family modules focus on semantic rendering rather than reinventing shared output plumbing
- remain host-agnostic enough that `pi` is an adapter, not the owner of the output contract

## Scope and non-scope

### In scope

- normalized success/failure result shapes for toolkit-backed tools
- structured details contract
- human-facing text contract
- truncation policy for tool-facing output
- stderr and warning policy
- normalization of lower-layer errors into toolkit-visible categories
- general rendering rules shared across Lean, knowledge-base, and informal tool families

### Out of scope

- low-level runtime capture limits and child-process ownership rules
- exact server-client request/response typing
- exact command selection for knowledge-base or informal tool families
- exact `pi` registration code
- UI-specific presentation details beyond plain text content

Those belong in companion design docs.

## Research basis and design consequences

This output plan is based on explicit research in both worktrees.

### Main-worktree reference points

Primary files studied:

- `../aftk/lambda/src/aftk-tools.ts`
- `../aftk/docs/aftk/README.md`

Important output observations from the earlier toolkit:

- Each tool currently returns a simple plain-text `content` block plus structured `details`.
- Error results use `isError: true` and a `details` object with a coarse `type`, such as:
  - `rpc_error`
  - `runtime_error`
- Human-facing formatting is intentionally concise and task-oriented.
- The earlier toolkit already has useful small renderers for:
  - goals
  - hover
  - term goal
  - infoview bundles
  - stepwise tactic results
- It already practices bounded text output through a `truncateText(...)` helper.
- That helper currently delegates to pi’s shared truncation defaults (`DEFAULT_MAX_BYTES`, `DEFAULT_MAX_LINES`, and `truncateHead(...)`) instead of defining a toolkit-owned truncation contract.
- Truncation is explicit in the returned text.
- Structured `details` currently vary by tool and error path, but they are not yet governed by one fully explicit cross-tool contract.
- Runtime stderr is mirrored to parent stderr rather than being deliberately integrated into tool output/diagnostics.

Main consequences for AFTK:

- AFTK should preserve the good parts:
  - plain text plus structured details,
  - concise renderers,
  - explicit truncation,
  - and error details richer than plain strings;
- but it should improve them by:
  - defining one deliberate cross-tool success/failure envelope,
  - normalizing CLI-backed and server-backed results more explicitly,
  - and making stderr/diagnostics policy part of the design rather than an accident of subprocess wiring.

### Repository reference points

Files studied:

- `docs/server/protocol.md`
- `docs/knowledgebase/cli.md`
- `docs/informal/cli.md`
- `plans/toolkit.md`
- `plans/toolkit/runtime.md`
- `plans/toolkit/server-client.md`

Important output observations from AFTK:

- The server already returns structured JSON-RPC result objects with small deterministic shapes.
- The knowledge-base CLI supports JSON and text modes, and its JSON success format uses a stable envelope with fields like:
  - `command`
  - `root`
  - `ok`
  - `result`
  - `warnings`
- In current implementation, the knowledge-base CLI’s raw `command` field uses exact dot-separated identifiers such as:
  - `metadata.validate`
  - `validate.storage`
  - `search.text`
  - `relationships.related`
- The informal CLI also supports JSON and text, but its JSON success format is command-shaped rather than using the knowledge-base envelope.
- In current implementation, informal success JSON is centered on a `data` field and may additionally carry `modules`, `target`, `mode`, and `bodyMode` depending on the command.
- The current rich `present` payload already distinguishes body modes structurally and uses `body.kind` plus preview `truncated` metadata rather than only flat text.
- The informal CLI failure JSON includes structured error information and `ok: false`.
- The lower informal implementation also sorts declaration/reference rows, dependency rows/leaves, tags, authors, relationship lines, and Lean-ref lines deterministically before rendering or JSON emission.
- The three lower-layer surfaces are therefore already machine-readable, but they do **not** use the same output conventions.
- The top-level toolkit plan explicitly settles that:
  - structured details are the stronger compatibility contract,
  - outputs should remain bounded,
  - and lower-layer differences should be normalized deliberately rather than hidden carelessly.

Main consequences for AFTK:

- toolkit-backed tools should prefer lower-layer JSON/structured outputs and then render their own concise text from parsed structured data;
- the toolkit should define one normalized output envelope above all three lower-layer styles;
- and the output contract should distinguish machine-facing details from display text instead of treating CLI text rendering as the canonical machine interface.

## Core output decisions

The v1 toolkit output design should make the following choices explicit.

### 1. Distinguish raw lower-layer results from normalized toolkit tool results

The toolkit should separate three conceptual levels:

1. **raw lower-layer result**
   - server JSON-RPC result or error
   - knowledge-base CLI JSON/text output and exit code
   - informal CLI JSON/text output and exit code
2. **normalized toolkit outcome**
   - a structured success/failure value used inside the toolkit
3. **host-facing tool result**
   - the final object returned to `pi` or another host, including concise text and structured details

This separation matters because it prevents:

- raw CLI envelopes from becoming the stable public toolkit contract,
- host-specific return shapes from infecting lower client layers,
- and ad hoc string formatting from becoming the only representation of success or failure.

### 2. Make structured details the stronger compatibility contract

The human-facing text should be helpful, but the stronger contract should be the structured details payload.

That means:

- higher layers should be able to rely on structured fields like ids, counts, ranges, codes, and normalized error categories
- human text may improve over time without counting as a breaking change, as long as it preserves basic intent
- if there is tension between preserving structure and preserving prose formatting, structure wins

### 3. Every tool result should carry concise text plus structured details

Toolkit-backed tools should return both:

- a concise text presentation for immediate reading
- a structured details payload for machine consumption

The v1 host-facing convention should remain close in spirit to the earlier toolset:

- `content`: one plain-text content block
- `details`: structured JSON-serializable payload
- `isError`: explicit on failures

A practical v1 rule is:

- success results omit `isError` or set it false
- failure results set `isError: true`
- all results include `details`
- all results use exactly one text content item in v1

### 4. Prefer toolkit-rendered text over relayed lower-layer text

For CLI-backed tool families, the toolkit should generally request JSON/structured lower-layer output and then render its own concise text from the parsed structured result.

So the default should be:

- knowledge-base CLI tools call `--format json`
- informal CLI tools call `--format json`
- toolkit renderers produce the final tool text

This gives the toolkit:

- a stable machine-facing structured basis,
- coherent cross-tool formatting,
- and freedom to keep host text concise without depending on lower-layer text formatting quirks.

Lower-layer text mode should remain available for:

- debugging,
- fallback when no structured output exists,
- or intentional pass-through tools if a later doc justifies them.

### 5. Use one normalized success envelope across all tool families

The toolkit should define one normalized success-details shape used by Lean, knowledge-base, and informal tools.
The exact TypeScript names can still evolve, but the conceptual contract should be stable.

A success details object should carry at least:

- `ok: true`
- `tool`: toolkit tool name
- `family`: `lean` | `knowledgebase` | `informal`
- `backend`: normalized backend metadata
- `result`: structured family-specific result payload
- `warnings`: structured warnings array
- optional truncation and diagnostic metadata

This lets higher layers write generic logic such as:

- “if `details.ok` and `details.family === "knowledgebase"`, inspect `details.result`”
- “if `details.warnings.length > 0`, surface a warning badge”

without needing to know whether the tool was server-backed or CLI-backed.

### 6. Use one normalized failure envelope across all tool families

The toolkit should likewise define one normalized failure-details shape.
A failure details object should carry at least:

- `ok: false`
- `tool`
- `family`
- `backend`
- `error`: normalized structured error object
- optional warnings and diagnostic metadata

This gives the toolkit a single place to express failures such as:

- server RPC errors
- CLI not-found/usage/validation/conflict failures
- runtime spawn failures
- timeout failures
- cancellation failures
- protocol-shape failures

### 7. Normalize error categories, but preserve source-specific codes

The output layer should normalize failures enough to make them comparable across tool families, but it should not erase lower-layer specificity.

So each normalized error should carry both:

- a **normalized category** such as:
  - `usage`
  - `not_found`
  - `validation`
  - `conflict`
  - `operational`
  - `tactic_failed`
  - `file_not_open`
  - `file_changed`
  - `worker_unavailable`
  - `stale_node`
  - `protocol`
  - `timeout`
  - `cancelled`
  - `runtime`
- and the **source-specific code** where available, such as:
  - server error code `-32011`
  - CLI exit code `4`
  - CLI error code string like `node.notFound`

This preserves the balance between consistency and fidelity.

### 8. Keep text short, deterministic, and task-oriented

Human-facing text should not be treated as a raw dump of lower-layer output.
Instead it should:

- start with the most useful summary information first
- use deterministic ordering
- avoid unnecessary prose flourishes
- avoid stack traces and verbose process diagnostics by default
- present empty/no-result cases clearly
- be optimized for quick reading in an agent loop

### 9. Keep outputs bounded and make truncation explicit

The toolkit should preserve the earlier discipline of bounded output, but make it a cross-tool contract.

Truncation should therefore:

- be explicit in returned text
- record truncation metadata in structured details
- distinguish display truncation from runtime capture limits
- prefer semantic truncation where possible over blind string chopping

### 10. Treat stderr as diagnostics, not primary content

Process stderr is important, but it should not dominate ordinary success text.
The output layer should therefore treat stderr primarily as diagnostic metadata.

Default rule:

- success text does not include stderr
- failure text includes stderr only when a short excerpt materially clarifies the failure
- details may carry a bounded stderr excerpt or structured stderr field

### 11. Preserve warnings as first-class structured data

Some lower-layer commands already return warnings structurally, especially the knowledge-base CLI envelope.
The toolkit should preserve warnings explicitly rather than collapsing them into prose.

Warnings should be carried in a structured `warnings` array on both success and failure details where relevant.
Text rendering may mention that warnings exist, but the structured warnings list is the stronger contract.

### 12. Separate semantic result data from diagnostics

The structured result for a successful tool should not be polluted with process diagnostics such as:

- exit code
- signal
- stderr excerpt
- truncation notices

Those belong in separate fields like:

- `backend`
- `warnings`
- `diagnostics`
- `truncation`

This keeps the semantic `result` payload clean and easier for higher layers to consume.

## Normalized host-facing result contract

The exact implementation types can still evolve, but the v1 output contract should look conceptually like this.

### Host-facing wrapper

Toolkit-backed tools should return an object conceptually like:

```ts
{
  content: [{ type: "text", text: string }],
  details: ToolkitToolDetails,
  isError?: boolean
}
```

The important constraints are:

- exactly one text content item in v1
- `details` always present
- `isError: true` on failure

### Success details shape

A normalized success details object should conceptually look like:

```ts
{
  ok: true,
  tool: string,
  family: "lean" | "knowledgebase" | "informal",
  backend: ToolkitBackendInfo,
  result: unknown,
  warnings: ToolkitWarning[],
  truncation?: ToolkitTruncationInfo,
  diagnostics?: ToolkitDiagnostics
}
```

### Failure details shape

A normalized failure details object should conceptually look like:

```ts
{
  ok: false,
  tool: string,
  family: "lean" | "knowledgebase" | "informal",
  backend: ToolkitBackendInfo,
  error: ToolkitToolError,
  warnings: ToolkitWarning[],
  truncation?: ToolkitTruncationInfo,
  diagnostics?: ToolkitDiagnostics
}
```

### Backend metadata shape

`backend` should identify where the result came from.
A practical v1 shape is one of:

- server-backed:

```ts
{
  kind: "server",
  method: string
}
```

- knowledge-base CLI-backed:

```ts
{
  kind: "knowledgebase_cli",
  command: string,
  exitCode?: number,
  root?: string
}
```

- informal CLI-backed:

```ts
{
  kind: "informal_cli",
  command: string,
  exitCode?: number,
  root?: string,
  modules?: string[]
}
```

For CLI-backed families, `backend.command` should preserve the exact lower-layer command identifier where one exists.
That means values such as:

- knowledge-base: `validate.storage`, `search.text`, `relationships.related`
- informal: `decls`, `deps`, `present`

rather than a second toolkit-invented command spelling.
The exact fields may vary per family, but the backend kind should always be explicit.

### Warning shape

A warning should be structured enough to be useful programmatically.
A practical conceptual shape is:

```ts
{
  message: string,
  code?: string,
  source?: string
}
```

### Diagnostic shape

Diagnostics should carry operational metadata such as:

- stderr excerpt
- stdout excerpt when useful on failure
- exit code
- signal
- duration
- whether timeout or forced termination occurred

They should be clearly separated from the semantic `result` payload.

### Truncation shape

Truncation metadata should carry at least:

- whether text content was truncated
- whether structured details were truncated
- original vs displayed sizes where available
- which fields were truncated if semantic truncation was field-specific

## Normalized error contract

The output layer should define one normalized error object shape used across tool families.

A practical conceptual shape is:

```ts
{
  kind: "rpc" | "cli" | "runtime" | "protocol" | "timeout" | "cancelled",
  category: string,
  message: string,
  code?: string | number,
  data?: unknown
}
```

### Error-kind rules

#### `rpc`

Use for valid JSON-RPC error responses from `aftk_server`.
These should preserve:

- method name in backend metadata
- numeric server error code
- error message
- error data

#### `cli`

Use for non-zero CLI outcomes or structured CLI failure JSON where the CLI itself reported a domain failure.
These should preserve:

- exit code
- CLI error code string where present
- CLI error message
- relevant root/command metadata

#### `runtime`

Use for configuration, spawn, IO, or general process/runtime failures that are not protocol-shaped lower-layer errors.

#### `protocol`

Use when the toolkit detects malformed or incompatible machine output, such as:

- malformed JSON-RPC line from the server
- invalid JSON envelope from a CLI in JSON mode
- method result shape incompatible with the documented contract

#### `timeout`

Use when a configured timeout expires.
This remains distinct from runtime and CLI-domain failure.

#### `cancelled`

Use when the caller’s `AbortSignal` cancels the operation.
This remains distinct from timeout.

### Error-category mapping rules

The output layer should define normalized category mappings like the following.

### Server RPC error-code mapping

- `-32001` -> `tactic_failed`
- `-32010` -> `file_not_open`
- `-32011` -> `file_changed`
- `-32012` -> `worker_unavailable`
- `-32013` -> `stale_node`
- other server-family codes -> `operational` unless a later doc refines them
- standard JSON-RPC invalid params -> `usage` or `protocol`, depending on whether the issue is caller params or incompatible server output

### Knowledge-base / informal CLI exit-code mapping

- `2` -> `usage`
- `3` -> `not_found`
- `4` -> `validation`
- `5` -> `conflict`
- `1` -> `operational`

This mapping gives higher layers a shared vocabulary across both CLI families while preserving the raw exit code separately.

### Runtime mapping

- timeout error -> `timeout`
- cancellation error -> `cancelled`
- configuration/startup/process errors -> `runtime`
- malformed machine output -> `protocol`

## Text rendering rules

The output layer should define common text-rendering expectations across all tool families.

### General text rules

Success text should:

- be concise
- be deterministic
- avoid raw JSON when a semantic renderer exists
- front-load the most useful information
- avoid process/debug noise

Failure text should:

- identify the failure source clearly
- include normalized meaning where useful
- avoid overwhelming the caller with diagnostics by default
- still preserve full structured details for programmatic inspection

### Single-item vs multi-item rendering

#### Single-item results

For results like:

- one hover
- one goal bundle
- one knowledge-base node show result
- one informal declaration or reference result

text should usually be a focused block rather than a list.

#### Multi-item results

For results like:

- multiple goals
- search/list hits
- dependency rows
- multi-step tactic results

text should usually:

- include a brief summary or count
- use stable ordering
- present one item per bullet/numbered block where that aids readability

### Empty-result wording

The toolkit should use stable, explicit empty-result wording rather than returning blank text.
Examples of the intended style are already visible in the earlier toolkit:

- `No hover information at this location.`
- `No goal information at this location.`
- `No term goal information at this location.`
- `No goals.`

Equivalent explicit wording should be used for CLI-backed empty cases too.

### Multi-section renderers

For compound results like:

- infoview bundles
- validation reports
- stepwise tactic execution

text may use section headers and separators.
The earlier `formatInfoViewResult(...)` pattern is a good reference point in spirit.

## Truncation policy

The output layer should own user-facing truncation policy.
This is distinct from the runtime’s internal capture limits.

### What should be truncated

Potentially large things that may need display truncation include:

- long hover text
- full goal or infoview renderings
- long knowledge-base body previews
- long validation/search results
- long dependency lists
- long multi-step tactic transcripts
- stderr excerpts on failure

### What should not be truncated casually

The toolkit should avoid truncating semantically essential short structured data such as:

- ids
- exit codes
- error categories
- node ids
- file paths when they are the main result
- small arrays of goals or references

If a structured payload itself becomes very large, truncation should be semantic and explicit, not an accidental partial object corruption.

### Preferred truncation order

When output is too large, prefer this order:

1. shorten human-facing text first
2. preserve the main semantic summary in text
3. preserve full or near-full structured details where safe
4. if structured details must also be truncated, do so semantically and mark it explicitly in `truncation`

### Truncation metadata expectations

When truncation happens, the structured details should record at least:

- that truncation happened
- whether it affected text, details, or both
- an estimate of original vs displayed size where practical

The text content should also say that it was truncated.

## Lower-layer normalization rules

The output layer should define how each lower-layer style maps into the normalized toolkit contract.

### Server-backed tools

Server-backed Lean tools already receive structured JSON-RPC results.
For them, normalization should mainly mean:

- mapping method result into family-specific `result`
- mapping server JSON-RPC errors into normalized `error`
- rendering concise text from the structured server result
- attaching backend metadata like `{ kind: "server", method }`

### Knowledge-base CLI-backed tools

Knowledge-base CLI tools should generally use `--format json` and normalize:

- `command`
- `root`
- `ok`
- `result`
- `warnings`
- structured `error`

into the toolkit success/failure envelope.

The toolkit should not simply embed the whole knowledge-base JSON envelope as its stable `details` contract.
Instead, it should:

- preserve semantically useful parts
- move backend metadata into `backend`
- move warnings into `warnings`
- place the meaningful command result under `result`
- preserve error code/message under normalized `error`

### Informal CLI-backed tools

Informal CLI tools should likewise use `--format json` and normalize command-shaped outputs into the same toolkit contract.

This is especially important because the informal CLI does **not** already match the knowledge-base envelope shape.
The toolkit should absorb that difference so higher layers do not need two separate conventions.
It should also preserve lower-layer structured fields that already carry useful semantics, such as:

- `data` payload boundaries,
- `target` for targeted commands,
- `mode` / `bodyMode` for `deps` and `present`,
- and `InformalBodyPresentation.preview(..., truncated := true)` metadata for preview-mode body rendering.

### Raw lower-layer payload retention

For debugging or tests, it may be useful to retain raw parsed lower-layer payloads.
If the toolkit does this, they should live in a clearly non-primary diagnostic field such as:

- `diagnostics.raw`

or a similarly explicit location.
They should **not** be the main stable contract.

## Stderr handling rules

The output layer should make stderr policy explicit.

### On success

On success:

- stderr is usually omitted from text
- stderr is omitted from details unless it is materially relevant or a warning policy requires it
- if retained, it should live in diagnostics and remain bounded

### On failure

On failure:

- a short stderr excerpt may be included in text if it materially clarifies the cause
- full or longer stderr excerpts should live in diagnostics
- stderr should never replace the normalized error category/code/message as the primary failure representation

### Why stderr should remain secondary

Stderr is often noisy, unstable, and not a reliable machine contract.
It is valuable diagnostic context, but it should not become the semantic API.

## Warnings policy

Warnings should be visible but not noisy.

### Structured warnings

All structured warnings returned by lower layers should be preserved in `warnings`.

### Text rendering of warnings

Text should mention warnings only when:

- there are few of them and they materially affect interpretation
- or the result is otherwise small and the warning is important

For large or numerous warnings, text should say something like:

- `Warnings: 3 (see details)`

rather than dumping them all inline.

## Recommended output helper responsibilities

Within the layout settled in `plans/toolkit/layout.md`, the output area should likely be refined as follows.

### `src/toolkit/output/result.ts`

Own:

- normalized success/failure detail types
- normalized error and warning types
- helper builders for success and failure host-facing tool results
- normalization helpers shared across tool families

### `src/toolkit/output/truncate.ts`

Own:

- user-facing text truncation helpers
- semantic list/body truncation helpers where practical
- truncation metadata builders

### `src/toolkit/output/render.ts`

Own:

- shared small renderers used across tool families
- common text-building helpers for blocks, sections, counts, and empty states
- error text renderers that consume normalized error details

Tool-family-specific semantic renderers may still live in their own modules when they are strongly domain-specific, but they should use the shared output contract and shared truncation helpers.

## Boundaries and anti-patterns

The output layer should explicitly avoid the following mistakes.

### 1. No raw lower-layer text as the default machine contract

The toolkit should not require higher layers to parse CLI text or free-form hover prose to recover structure.

### 2. No family-specific details shape without a shared envelope

Lean, knowledge-base, and informal tools can have different `result` payloads, but the surrounding success/failure structure should be shared.

### 3. No silent truncation

If output was truncated, both text and details should say so clearly.

### 4. No stderr dumps in ordinary success content

That makes outputs noisy and unstable.

### 5. No message-string scraping as the main failure interface

Use structured categories, codes, and data instead.

### 6. No accidental dependence on host-library truncation constants as the only source of truth

The toolkit may align with host defaults such as `pi` where useful, but the toolkit should own and document its own output contract.

### 7. No mixing semantic result data with process diagnostics

Keep `result`, `error`, `warnings`, `diagnostics`, and `truncation` clearly separate.

## Initial implementation checklist for this output design

Before the output layer can be considered in place, AFTK should reach at least this baseline:

- a shared normalized success/failure details contract exists
- host-facing tool results consistently include one text block plus structured details
- server, knowledge-base, and informal tool families all use that shared envelope
- normalized error kinds and categories exist and preserve source-specific codes
- text truncation helpers exist and add explicit truncation notices
- truncation metadata exists in details
- stderr handling is explicit and bounded
- warnings are preserved structurally
- tool-family renderers use structured lower-layer outputs rather than raw lower-layer text by default

## Summary

The AFTK toolkit should not let each tool family invent its own return shape.
Instead, it should define one cross-tool output contract built around:

- concise plain-text content for immediate reading,
- structured details as the stronger compatibility contract,
- explicit success/failure envelopes,
- normalized error categories with preserved source-specific codes,
- explicit warnings and diagnostics,
- and bounded, clearly signaled truncation.

That contract should sit above AFTK's heterogeneous lower-layer outputs:

- structured server JSON-RPC results,
- knowledge-base CLI JSON envelopes,
- and informal CLI command-shaped JSON.

By normalizing those carefully rather than flattening them away, the toolkit can remain both:

- practical for agents and humans to read,
- and reliable for later higher-level code to consume programmatically.
