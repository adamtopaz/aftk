# Toolkit implementation guide

This document is the component-level implementation map for the TypeScript toolkit layer.
It explains how the current package is organized, which files own which responsibilities, and where the pi integration and setup script fit.

## Public entrypoints and code roots

Main code pointers:

- curated public library root: `src/index.ts`
- compatibility shim: `index.ts`
- pi adapter helpers: `src/hosts/pi/index.ts`
- default pi extension entrypoint: `src/hosts/pi/extension.ts`
- Lake setup script: `lakefile.lean`

Package-export entrypoints from `package.json`:

- `.` -> `src/index.ts`
- `./pi` -> `src/hosts/pi/index.ts`
- `./pi-extension` -> `src/hosts/pi/extension.ts`

Operational lower-layer entrypoints targeted by the toolkit:

```text
lake exe aftk_server
lake exe aftk knowledgebase ...
lake exe aftk informal ...
lake run aftk_setup
```

## Component map

| Component | Main code | Responsibility |
| --- | --- | --- |
| Public library root | `src/index.ts` | Curated export surface for runtime, clients, tool factories, and shared types |
| Compatibility shim | `index.ts` | Transitional re-export of `src/index.ts` |
| Runtime context | `src/toolkit/runtime/options.ts` | Resolve cwd, project root, command specs, capture policy, and timeouts |
| Project-root discovery | `src/toolkit/runtime/project-root.ts` | Upward `lakefile.*` search and explicit-root validation |
| Executable resolution | `src/toolkit/runtime/executables.ts` | Default/override command specs for hub, knowledge-base CLI, and informal CLI |
| Runtime errors | `src/toolkit/runtime/errors.ts` | Typed configuration/process/timeout/cancellation/lifecycle/protocol failures |
| Subprocess helpers | `src/toolkit/runtime/subprocess.ts` | Managed long-running children, one-shot commands, termination escalation |
| CLI wrapper | `src/toolkit/runtime/cli.ts` | Thin one-shot dispatch to knowledge-base / informal CLI specs |
| Output truncation | `src/toolkit/output/truncate.ts` | Shared rendered-text bounding and truncation metadata |
| Output/result envelope | `src/toolkit/output/result.ts` | Normalized success/failure details, diagnostics, warnings, error mapping |
| Output render helpers | `src/toolkit/output/render.ts` | Small shared text renderers for ranges, goals, sections, and generic errors |
| Server protocol mirror | `src/toolkit/server/protocol.ts` | TypeScript mirror of the public `aftk_server` method family plus validators |
| Managed server client | `src/toolkit/server/client.ts` | Lazy-start managed hub client, request correlation, protocol checking |
| Knowledge-base CLI client | `src/toolkit/knowledgebase/client.ts` | JSON-envelope parsing and normalized typed access to `aftk knowledgebase` |
| Informal CLI client | `src/toolkit/informal/client.ts` | Command-shaped JSON parsing and normalized typed access to `aftk informal` |
| Shared tool helpers | `src/toolkit/tools/common.ts` | Tool-definition type, small schema DSL, input validation, family selection |
| Lean tool family | `src/toolkit/tools/lean.ts` | `aftk_*` tool definitions over the managed server client |
| Knowledge-base tool family | `src/toolkit/tools/knowledgebase.ts` | `knowledgebase_*` query/report tool definitions over the CLI client |
| Informal tool family | `src/toolkit/tools/informal.ts` | `informal_*` tracking/dependency/presentation tool definitions over the CLI client |
| Aggregate toolset | `src/toolkit/tools/aggregate.ts` | Shared runtime + selected family assembly + managed shutdown |
| Pi adapter helpers | `src/hosts/pi/index.ts` | Direct SDK custom-tools helper and extension-style registration helper |
| Pi extension entrypoint | `src/hosts/pi/extension.ts` | Default extension registration using `process.cwd()` |
| Lake setup script | `lakefile.lean` | Project-local pi shim/prompt generation for `aftk_setup` |

## Root and export surfaces

### `src/index.ts`

This is the curated public package root.
It re-exports:

- runtime context creation and runtime policy types
- runtime error classes
- `AftkServerClient` and server protocol types
- shared output/result helpers
- dedicated tool-family factories
- the aggregate `createToolkitTools(...)` factory
- shared tool-definition/schema helpers
- typed knowledge-base and informal CLI clients

This file is the best first stop for understanding what the package considers public.

### `index.ts`

This is a tiny repository-root shim:

```ts
export * from "./src/index.ts";
```

It does not own implementation logic.
The real package layout lives under `src/`.

### `package.json`

This file defines the package-facing entrypoints and scripts.
Important implementation facts:

- package name: `aftk-toolkit`
- module mode: ESM (`"type": "module"`)
- pi metadata points at `src/hosts/pi/extension.ts`
- toolkit scripts are separate from `lake test`

## Runtime components

### `src/toolkit/runtime/options.ts`

This file builds the shared runtime context.

Important types:

- `ToolkitTimeoutPolicy`
- `ToolkitCapturePolicy`
- `ToolkitDebugEvent`
- `ToolkitRuntimeOptions`
- `ToolkitRuntimeContext`

Important values and functions:

- `DEFAULT_TIMEOUT_POLICY`
- `DEFAULT_CAPTURE_POLICY`
- `createToolkitRuntimeContext(...)`
- `debugRuntimeEvent(...)`

Implementation role:

- resolves `cwd`
- resolves `projectRoot`
- merges environment overrides
- resolves lower-layer executable specs
- installs timeout/capture/debug/stderr-tee policy into one reusable object

### `src/toolkit/runtime/project-root.ts`

This file owns Lean-project discovery.

Important functions:

- `findProjectRoot(startDir)`
- `resolveProjectRoot({ cwd, projectRoot? })`

Implementation role:

- walks upward looking for `lakefile.toml` or `lakefile.lean`
- allows an explicit project-root override
- rejects explicit roots that are not directories
- throws `ToolkitConfigError` if discovery fails

Important current detail:

- an explicit `projectRoot` only needs to be a directory; it is not revalidated as a Lake root

### `src/toolkit/runtime/executables.ts`

This file resolves the actual subprocess command specs the toolkit will use.

Important types:

- `CommandSpecInput`
- `ResolvedCommandSpec`
- `ToolkitExecutableOverrides`
- `ToolkitExecutableSpecs`

Important functions:

- `resolveToolkitExecutableSpecs(...)`

Default command specs today:

- hub: `lake exe aftk_server`
- knowledgebase: `lake exe aftk knowledgebase`
- informal: `lake exe aftk informal`

Implementation role:

- merges defaults with caller overrides
- resolves path-like commands and override cwd values
- makes every backend invocation explicit and inspectable

### `src/toolkit/runtime/errors.ts`

This file defines the shared runtime error vocabulary.

Important types and classes:

- `ToolkitRuntimeErrorKind`
- `ToolkitRuntimeErrorDetails`
- `ToolkitRuntimeError`
- `ToolkitConfigError`
- `ToolkitProcessStartError`
- `ToolkitProcessError`
- `ToolkitTimeoutError`
- `ToolkitCancellationError`
- `ToolkitLifecycleError`
- `ToolkitProtocolError`
- `isToolkitRuntimeError(...)`

Implementation role:

- gives the whole toolkit one structured operational error family
- keeps process/runtime failures distinct from lower-layer semantic failures
- lets higher layers retain diagnostics without scraping free-form text

### `src/toolkit/runtime/subprocess.ts`

This is the operational core of the toolkit runtime.

Important types:

- `CompletedCommand`
- `RunCommandOptions`
- `ManagedProcessExitInfo`
- `ManagedSubprocessOptions`
- `ManagedStopOptions`

Important functions and classes:

- `ManagedSubprocess`
- `runCommand(...)`
- `terminateChildProcess(...)`
- `waitForProcessExit(...)`

Implementation role:

- owns the lazy-managed child-process abstraction used by the server client
- owns the one-shot command helper used by knowledge-base and informal CLI clients
- captures bounded stderr tails
- supports local timeout and `AbortSignal` cancellation
- escalates shutdown from graceful request -> `SIGTERM` -> `SIGKILL`

Important design boundary:

- this layer manages processes and capture limits
- it does **not** interpret server/CLI semantics

### `src/toolkit/runtime/cli.ts`

This file is intentionally thin.

Important definitions:

- `ToolkitCliFamily`
- `runToolkitCliCommand(...)`

Implementation role:

- maps `"knowledgebase"` and `"informal"` to the resolved executable specs
- reuses `runCommand(...)`
- keeps CLI-family dispatch out of the higher-level clients

## Output components

### `src/toolkit/output/truncate.ts`

This file owns rendered-text truncation.

Important definitions:

- `ToolkitTextTruncationPolicy`
- `ToolkitTextTruncationInfo`
- `DEFAULT_TEXT_TRUNCATION_POLICY`
- `truncateText(...)`

Current rendered-text limits:

- 200 lines
- 20 KiB

Implementation role:

- bounds tool-facing text output independently of larger runtime capture limits
- adds explicit truncation notices and metadata

### `src/toolkit/output/result.ts`

This file defines the normalized tool-result contract.

Important types:

- `ToolkitFamily`
- `ToolkitWarning`
- `ToolkitDiagnostics`
- `ToolkitTruncationInfo`
- `ToolkitBackendInfo`
- `ToolkitErrorKind`
- `ToolkitToolError`
- `ToolkitSuccessDetails`
- `ToolkitFailureDetails`
- `ToolkitToolResult`

Important functions:

- `buildSuccessResult(...)`
- `buildFailureResult(...)`
- `diagnosticsFromRuntimeLike(...)`
- `toolErrorFromUnknown(...)`
- `cliCategoryFromExitCode(...)`

Implementation role:

- gives every tool family the same top-level result shape
- centralizes truncation application
- centralizes diagnostics extraction from runtime errors
- normalizes timeout/cancelled/protocol/runtime failures

### `src/toolkit/output/render.ts`

This file contains small shared text helpers.

Important functions:

- `renderRange(...)`
- `renderGoals(...)`
- `renderBulletList(...)`
- `renderSection(...)`
- `joinSections(...)`
- `renderGenericErrorText(...)`

Implementation role:

- avoids duplicating small deterministic text formatters across tool families
- stays intentionally lightweight rather than becoming a large presentation system

## Server-backed client components

### `src/toolkit/server/protocol.ts`

This file is the TypeScript mirror of the public `aftk_server` protocol.

Important definitions:

- public request/result types for every hub method
- `AftkServerProtocolMap`
- `AftkServerMethod`
- `ParamsFor<M>` / `ResultFor<M>`
- `AftkServerErrorCode`
- `classifyAftkServerErrorCode(...)`
- method-aware result validators such as `isHoverResult(...)`, `isRunTacticResult(...)`, and `validateMethodResult(...)`

Implementation role:

- keeps the TypeScript client aligned with the documented server surface
- preserves method-specific result quirks like nullable hover/goal responses
- centralizes error-code classification

### `src/toolkit/server/client.ts`

This file implements the managed server client.

Important types and classes:

- `AftkServerRequestOptions`
- `AftkServerRpcError`
- `AftkServerProtocolError`
- `CreateAftkServerClientOptions`
- `AftkServerClient`

Important methods:

- `start()`
- `isRunning()`
- `request(...)`
- `open(...)`
- `close(...)`
- `loadNode(...)`
- `getHover(...)`
- `getPlainGoal(...)`
- `getPlainTermGoal(...)`
- `getInfoView(...)`
- `getGoals(...)`
- `runTactic(...)`
- `runTacticSteps(...)`
- `shutdown()`
- `stop(graceful?)`

Implementation role:

- lazily starts the managed `aftk_server` process
- line-buffers newline-delimited JSON-RPC responses
- allocates numeric request ids
- validates envelopes and method-specific result shapes
- rejects all pending requests if the hub exits unexpectedly
- treats malformed non-empty stdout as protocol corruption and stops the process

Important current detail:

- aborting a request cancels the local waiting promise only; it does not remotely cancel an already-sent server request

## CLI-backed client components

### `src/toolkit/knowledgebase/client.ts`

This file wraps the knowledge-base CLI in JSON mode.

Important exported types include:

- node/metadata/search/relationship/validation result types
- `KnowledgeBaseCliSuccess<T>`
- `KnowledgeBaseCliFailure`
- `KnowledgeBaseCliResponse<T>`
- command option types such as `KnowledgeBaseCommandOptions`, `KnowledgeBaseListOptions`, `KnowledgeBaseShowOptions`, and `KnowledgeBaseSearchOptions`

Important class and methods:

- `KnowledgeBaseClient`
- `status(...)`
- `list(...)`
- `show(...)`
- `searchText(...)`
- `searchTag(...)`
- `relationships(...)`
- `validateStorage(...)`
- `validateNode(...)`
- `validateMetadata(...)`
- `validateAll(...)`

Implementation role:

- runs `lake exe aftk knowledgebase --format json ...`
- parses the CLI's stable envelope
- converts JSON payloads into typed TypeScript structures
- preserves CLI warnings and process diagnostics

Important current detail:

- validation reports are returned as successful CLI responses even when the report itself has `ok = false` and the process exit code is `4`

### `src/toolkit/informal/client.ts`

This file wraps the informal CLI in JSON mode.

Important exported types include:

- declaration/reference/dependency/presentation result types
- `InformalCliSuccess<T>`
- `InformalCliFailure`
- `InformalCliResponse<T>`
- environment and presentation option types such as `InformalEnvironmentOptions`, `InformalDepsOptions`, and `InformalPresentOptions`

Important class and methods:

- `InformalClient`
- `status(...)`
- `decls(...)`
- `decl(...)`
- `refs(...)`
- `ref(...)`
- `deps(...)`
- `present(...)`

Implementation role:

- runs `lake exe aftk informal --format json ...`
- parses the informal CLI's command-shaped JSON outputs
- keeps environment-backed and presentation-backed command forms explicit
- preserves process diagnostics on both success and failure

## Tool-definition components

### `src/toolkit/tools/common.ts`

This file defines the shared host-facing tool shape used by the package.

Important definitions:

- `ToolkitToolDefinition`
- `ToolkitManagedToolset`
- `ToolkitStatelessToolset`
- `ToolkitFamilySelection`
- `ToolInputError`
- `Schema`

Important helper functions:

- `requireString(...)`
- `optionalString(...)`
- `requirePositiveInteger(...)`
- `optionalBoolean(...)`
- `requireNonEmptyString(...)`
- `requireStringArray(...)`
- `optionalEnum(...)`
- `normalizeToolPath(...)`
- `enabledFamilies(...)`

Implementation role:

- gives every tool family one shared definition type
- provides a tiny schema DSL for host adapters such as pi
- centralizes common parameter validation
- strips a leading `@` from file paths where the Lean tool family wants that compatibility behavior

### `src/toolkit/tools/lean.ts`

This file defines the Lean-facing server-backed tool family.

Important exports:

- `createAftkLeanTools(...)`
- compatibility alias `createAFTKTools(...)`

Implementation role:

- builds the managed `AftkServerClient`
- defines the `aftk_*` tool list and parameter schemas
- renders concise text for hover/goals/infoview/tactic flows
- maps known server RPC errors into more actionable user text and structured error categories

Important design boundary:

- it is a semantic wrapper over the reusable client
- it is **not** a second JSON-RPC client implementation

### `src/toolkit/tools/knowledgebase.ts`

This file defines the selected knowledge-base tool surface.

Important export:

- `createKnowledgeBaseTools(...)`

Implementation role:

- maps a focused query/reporting subset of the CLI to `knowledgebase_*` tools
- renders concise summaries for list/show/search/relationship/validation results
- preserves validation-report semantics as successful tool calls with structured report data
- turns non-report CLI failures into normalized tool failures

### `src/toolkit/tools/informal.ts`

This file defines the informal tool surface.

Important export:

- `createInformalTools(...)`

Implementation role:

- maps the current informal CLI surface to `informal_*` tools
- distinguishes environment-backed queries from direct presentation
- renders concise tracking/dependency/presentation text
- maps common informal failure cases into normalized categories

### `src/toolkit/tools/aggregate.ts`

This file assembles the package's combined toolset.

Important definitions:

- `CreateToolkitToolsOptions`
- `ToolkitAggregateToolset`
- `createToolkitTools(...)`

Implementation role:

- creates one shared runtime context
- selects tool families by `families` flags
- collects stateless CLI-backed tool families and managed server-backed tool families together
- exposes `shutdown(graceful?)` and `dispose()` over the managed portions only

Important current detail:

- only the Lean/server-backed family contributes managed shutdown state today
- knowledge-base and informal tools are one-shot CLI tools and do not need cleanup

## Pi adapter components

### `src/hosts/pi/index.ts`

This file contains the thin pi-specific mounting helpers.

Important definitions:

- `PiExtensionAPILike`
- `PiToolkitIntegration`
- `createPiToolkitCustomTools(...)`
- `registerToolkitExtension(...)`

Implementation role:

- keeps pi-specific registration outside the reusable toolkit core
- supports a direct SDK-style `customTools` path
- supports extension-style registration into pi
- adds the `aftk-extension-stop` command
- hooks `session_shutdown` for cleanup

### `src/hosts/pi/extension.ts`

This is the default extension entrypoint.

Implementation role:

- exports a default function for pi discovery/loading
- calls `registerToolkitExtension(pi, { cwd: process.cwd() })`
- stays intentionally tiny and declarative

## Setup-script component

### `lakefile.lean`

Besides the Lean package configuration, this file implements the `aftk_setup` Lake script.

Important helper definitions:

- generated-file marker helpers
- import-specifier computation helpers
- managed-write classification helpers
- `runAftkSetup`
- `script aftk_setup (args) do ...`

Implementation role:

- discovers the current Lake workspace root and the `aftk` package location
- locates `src/hosts/pi/extension.ts`
- generates `.pi/extensions/aftk-toolkit.ts`
- generates `.pi/APPEND_SYSTEM.md`
- refuses to overwrite user-managed files without the generated marker
- supports `--help`

This script is documented in more detail in `docs/aftk_setup.md`.

## Related docs

- `docs/toolkit/overview.md`
- `docs/toolkit/testing.md`
- `docs/aftk_setup.md`
- `docs/architecture.md`
