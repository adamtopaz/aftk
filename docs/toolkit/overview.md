# Toolkit overview

The toolkit layer is the implemented TypeScript bridge above the Lean layers.
It packages the public server protocol and the knowledge-base / informal CLIs into reusable Node-compatible clients and agent-facing tool definitions.

Public entrypoints:

- package library root: `src/index.ts` (exported as `.` from `package.json`)
- pi adapter helpers: `src/hosts/pi/index.ts` (exported as `./pi`)
- toolkit pi extension entrypoint: `src/hosts/pi/extension.ts` (exported as `./pi-extension`)
- logging pi extension entrypoint: `src/hosts/pi/logging-extension.ts` (exported as `./pi-logging-extension`)
- workspace setup script: `lake run aftk_setup`

There is **no standalone toolkit CLI**.
The toolkit is a library and host-integration layer that wraps lower-layer entrypoints.

For a component-by-component guide with direct code pointers, see `docs/toolkit/library.md`.
For the setup script that installs the local pi shims and appended prompt, see `docs/aftk_setup.md`.

## What is implemented

The current toolkit layer includes:

- shared runtime context creation with project-root discovery, executable resolution, timeout policy, and bounded capture policy
- typed runtime error classes for configuration, startup, process, timeout, cancellation, lifecycle, and protocol failures
- a managed `aftk_server` client that speaks newline-delimited JSON-RPC over stdio
- TypeScript protocol types and lightweight result validators for the public hub method family
- one-shot CLI clients for:
  - `lake exe aftk knowledgebase ...`
  - `lake exe aftk informal ...`
- a normalized toolkit result envelope with concise text, structured details, truncation metadata, warnings, and diagnostics
- three tool families:
  - Lean/server-backed `aftk_*`
  - CLI-backed `knowledgebase_*`
  - CLI-backed `informal_*`
- aggregate toolset construction with family selection and managed shutdown
- thin pi mounting helpers for both direct SDK use and extension-style registration
- a Lake setup script that installs project-local pi shims plus the appended AFTK prompt
- a pi logging extension that keeps session logs under `.aftk/logs/` and run-cost summaries under `.aftk/cost/`
- a dedicated TypeScript-side test suite under `tests/toolkit/`

## What it does not do

The toolkit deliberately does **not**:

- own canonical knowledge-base or informal data
- replace the lower-layer CLIs or server as the source of truth for semantics
- expose the full mutation/admin surface of the knowledge-base CLI in v1
- add server-side cancellation for in-flight hub requests
- implement the later AI autoformalization orchestration layer

So the toolkit should be understood as a practical integration layer, not as a second owner of lower-layer behavior.

## Package and export surface

The TypeScript package is described by `package.json`:

```json
{
  "name": "aftk-toolkit",
  "exports": {
    ".": "./src/index.ts",
    "./pi": "./src/hosts/pi/index.ts",
    "./pi-extension": "./src/hosts/pi/extension.ts",
    "./pi-logging-extension": "./src/hosts/pi/logging-extension.ts"
  }
}
```

The curated public library root in `src/index.ts` re-exports:

- runtime context creation and runtime error types
- server protocol types and the managed `AftkServerClient`
- output/result helpers
- the three dedicated tool-family factories
- the aggregate `createToolkitTools(...)` factory
- the knowledge-base and informal CLI-client layers
- shared tool-definition/schema helpers

There is also a small repository-root `index.ts` shim that simply re-exports `./src/index.ts`.
That file exists for transitional compatibility, but the real implementation surface lives under `src/`.

## Runtime model

The toolkit runtime is defined in `src/toolkit/runtime/`.
Its main operational rules are:

- `cwd` defaults to `process.cwd()`
- `projectRoot` defaults to the nearest ancestor containing `lakefile.toml` or `lakefile.lean`
- lower-layer commands run with `cwd = projectRoot` by default
- default command specs are:
  - `lake exe aftk_server`
  - `lake exe aftk knowledgebase`
  - `lake exe aftk informal`
- the managed hub process starts lazily when the first server request is sent
- one-shot CLI calls are spawned separately per command
- runtime capture limits are larger than user-facing text truncation limits

Default runtime policies today:

- operation timeout: `120_000ms`
- graceful shutdown timeout: `5_000ms`
- forced terminate / kill waits: `1_500ms` each
- command stdout capture limit: `5 MiB`
- command stderr tail limit: `256 KiB`
- managed-process stderr tail limit: `256 KiB`

## Tool families

### Lean / server-backed tools

These tools wrap the public `aftk_server` protocol closely:

- `aftk_open`
- `aftk_close`
- `aftk_load_node`
- `aftk_get_hover`
- `aftk_get_plain_goal`
- `aftk_get_plain_term_goal`
- `aftk_get_infoview`
- `aftk_get_goals`
- `aftk_run_tactic`
- `aftk_run_tactic_steps`
- `aftk_shutdown`

Important behavior:

- the family is session-oriented and explicit; callers must open files before most file-scoped queries
- path normalization is intentionally minimal and only strips a leading `@`
- node ids are treated as opaque transient server-owned handles
- known RPC error codes are rendered into more actionable text while still preserving structured details

### Knowledge-base tools

These tools wrap a selected query/reporting subset of the knowledge-base CLI:

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

Important behavior:

- every tool runs the CLI in `--format json` mode
- the TypeScript client parses the CLI envelope rather than scraping human text output
- validation-report commands remain **successful tool calls** even when the report itself contains errors and the CLI exits with code `4`
- the initial family is query-first; mutation/admin commands are still deferred

### Informal tools

These tools wrap the current informal CLI surface:

- `informal_status`
- `informal_decls`
- `informal_decl`
- `informal_refs`
- `informal_ref`
- `informal_deps`
- `informal_present`

Important behavior:

- environment-backed commands require `modules: string[]`
- direct presentation uses optional `root`, `mode`, and `body` options
- the TypeScript client parses command-shaped informal JSON output per command
- `informal_present` complements server hover; it does not replace `aftk_get_hover`

## Result model

Every toolkit tool returns the same top-level shape:

- `content: [{ type: "text", text: ... }]`
- `details: ...`
- optional `isError: true` on failures

The structured `details` payload is the stronger compatibility contract.
It includes:

- `ok`
- `tool`
- `family`
- `backend`
- `result` or `error`
- `warnings`
- optional `truncation`
- optional `diagnostics`

Text output is intentionally concise and bounded.
The shared truncation policy in `src/toolkit/output/truncate.ts` currently limits rendered text to:

- 200 lines
- 20 KiB

When truncation happens, the returned text includes an explicit notice and the details payload carries truncation metadata.

## Pi integration

The toolkit has a thin host-adapter layer in `src/hosts/pi/`.
There are three main pi-facing entrypoints:

### `createPiToolkitCustomTools(...)`

Defined in `src/hosts/pi/index.ts`.
It builds the aggregate toolkit and returns:

- `customTools`
- `dispose()`

This is the direct SDK-style path.

### `registerToolkitExtension(...)`

Also defined in `src/hosts/pi/index.ts`.
It:

- registers toolkit tools into pi
- adds an `aftk-extension-stop` command
- hooks pi `session_shutdown` to call `dispose()`

The default toolkit extension entrypoint in `src/hosts/pi/extension.ts` simply calls:

```ts
registerToolkitExtension(pi, { cwd: process.cwd() });
```

### `registerAftkLoggingExtension(...)`

Also exported from `src/hosts/pi/index.ts`.
It:

- redirects pi's session directory into `.aftk/logs/`
- mirrors session JSONL into `.aftk/logs/` when pi is configured elsewhere or with `--no-session`
- accumulates per-run usage from `agent_end`
- writes per-run summaries to `.aftk/cost/`

The logging extension entrypoint in `src/hosts/pi/logging-extension.ts` simply calls:

```ts
registerAftkLoggingExtension(pi);
```

So both pi extension entrypoints stay intentionally thin while the reusable logic lives in `src/hosts/pi/index.ts` and `src/hosts/pi/logging.ts`.

## Relationship to `aftk_setup`

`lake run aftk_setup` is the bridge between the toolkit package and project-local pi discovery.
It writes:

- `.pi/extensions/aftk-toolkit.ts`
- `.pi/extensions/aftk-logging.ts`
- `.pi/APPEND_SYSTEM.md`

The generated shims re-export the package's pi extension entrypoints from the resolved `aftk` package location.
The appended system prompt is generated from `src/hosts/pi/APPEND_SYSTEM.template.md` and adds AFTK-specific tool/workflow guidance for agents.
Once installed, the logging extension keeps project-local logs under `.aftk/logs/` and run-cost summaries under `.aftk/cost/`.

This script is documented separately in `docs/aftk_setup.md` because it is a Lake/workspace setup concern, not part of the reusable toolkit runtime itself.

## Current practical mental model

A good short mental model of the toolkit layer is:

- the Lean layers still own the semantics,
- the toolkit owns the Node/process/client/tool wrapping needed for agent use,
- and the pi adapters stay thin wrappers over reusable toolkit code.

If you keep that boundary in mind, the TypeScript side of the repository is much easier to navigate.

## Where to read next

- `docs/toolkit/library.md`
- `docs/toolkit/testing.md`
- `docs/aftk_setup.md`
- `docs/architecture.md`
