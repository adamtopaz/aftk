# Toolkit Layer Plan

## Status

Overall design/status document for the fourth layer of `aftk`.
This file now serves two purposes:

- it records the current implementation status of the toolkit layer
- it preserves the higher-level design rationale behind that implementation

Authoritative implementation docs for the landed toolkit live under:

- `docs/toolkit/overview.md`
- `docs/toolkit/library.md`
- `docs/toolkit/testing.md`
- `docs/aftk_setup.md`

## Plan implementation status

- Overall status: Implemented (initial v1), with deferred follow-ons
- Fully implemented: Yes, for the current v1 baseline
- Last updated basis: the current toolkit implementation in `src/index.ts`, `src/toolkit/**`, `src/hosts/pi/**`, `tests/toolkit/**`, `package.json`, and `lakefile.lean`
- Main deferred follow-ons: broader mutation/admin coverage, possible composite helpers, and the later AI autoformalization layer above the toolkit

This section is the single place for tracking the current status of the toolkit-layer plan.
The historical research sections below were useful while the layer was being built, but they should now be read as design background rather than as statements about the current codebase.

The practical definition of “implemented” for this plan is now satisfied by the current repository:

- a real TypeScript toolkit package exists under `src/`
- reusable non-pi-specific library code exists for talking to the lower layers
- the Lean-facing `aftk_*` family exists
- query-first knowledge-base and informal tool families exist
- pi integration is a thin adapter over reusable toolkit code
- process lifecycle, output shaping, and lower-layer integration are covered by dedicated TypeScript tests
- the implementation is documented clearly enough for future higher-layer work to build on it directly

## Historical note

Some research sections below still describe the earlier pre-implementation scaffold, including Bun-era placeholder files and the period before the toolkit was landed.
Treat those sections as historical design rationale only.
Current implementation behavior is documented in `docs/toolkit/**` and `docs/aftk_setup.md`.

## Purpose

The toolkit layer is the first TypeScript layer in the rewrite.
Its job is to turn the lower-layer services and CLIs into practical, agent-facing TypeScript interfaces.

In the rewrite, the lower layers now include:

- the knowledge-base layer,
- the informal layer,
- and the server/file-worker layer.

So the toolkit layer should not be understood as “just the old AFTK hub wrapper, rewritten in TypeScript.”
It should preserve the useful parts of that current wrapper while expanding to the broader layered architecture now present in AFTK.

Concretely, the toolkit layer should provide:

- reusable TypeScript clients and process-management helpers,
- tool definitions suitable for `pi` and other agent integrations,
- a normalized TypeScript-facing view over multiple lower-layer interfaces,
- and a clean foundation for the later AI autoformalization agent layer.

## Position in the layered architecture

The overall rewrite stack is:

1. Knowledge base layer
2. Informal layer
3. Server and file-worker layer
4. Toolkit layer
5. AI autoformalization agent layer

The toolkit layer sits directly above the first three implemented Lean layers.
It is the first place where AFTK should deliberately package those lower-layer capabilities for everyday machine use.

That means its role is different from the lower layers:

- it should **not** own canonical knowledge or Lean semantics,
- it should **not** reimplement lower-layer logic,
- and it should **not** yet become the AI orchestration layer.

Instead, it should provide the stable practical interfaces that the AI layer and external integrations can consume.

## Research basis and key findings

This plan is based on explicit research in both worktrees.
The most relevant files are listed here so later component docs can refer back to them quickly.

### Main-worktree toolkit reference points

Primary implementation files studied:

- `../aftk/lambda/src/aftk-tools.ts`
- `../aftk/lambda/src/aftk-extension.ts`

Primary docs studied:

- `../aftk/docs/aftk/README.md`
- `../aftk/README.md`
- `../aftk/docs/agent-playbook.md`
- `../aftk/docs/future/autoformalization-tools.md`
- `../aftk/package.json`
- `../aftk/tsconfig.json`

Key findings from that implementation:

- The canonical current TypeScript surface is `createAFTKTools(...)` in `lambda/src/aftk-tools.ts`.
- That function returns:
  - `tools` — a list of custom tool definitions,
  - `shutdown(graceful?)` — cleanup for the managed hub process.
- The current toolkit is strongly **server-centric**:
  - it wraps `aftk_server`,
  - mirrors the server JSON-RPC method family almost one-for-one,
  - and does not wrap the main-branch knowledge CLI or Informalize CLI.
- The current toolkit keeps all core logic in one TypeScript file:
  - a managed hub process client,
  - JSON-RPC request tracking,
  - timeout and shutdown behavior,
  - TypeBox parameter schemas,
  - and tool-result formatting.
- The current `AftkHubClient` lazily starts `lake exe aftk_server`, line-buffers newline-delimited JSON-RPC responses, tracks pending requests by id, and performs graceful shutdown with `SIGTERM`/`SIGKILL` fallback.
- The current toolkit reuses pi helper truncation defaults (`DEFAULT_MAX_BYTES`, `DEFAULT_MAX_LINES`, and `truncateHead(...)`) rather than owning a toolkit-specific truncation policy of its own.
- The current abort handling only cancels the local waiting promise; it does not cancel an already-sent hub request remotely.
- The current `aftk_shutdown` tool performs the semantic `shutdown` request and then explicitly clears owned child-process state with `client.stop(false)`.
- The current tool outputs are intentionally simple:
  - concise text for human consumption,
  - plus structured `details` for programmatic access.
- The current wrapper normalizes file paths by stripping a leading `@`, which is a useful integration detail for `pi`-style path passing.
- The current pi extension wrapper is deliberately thin:
  - it calls `createAFTKTools(...)`,
  - registers each tool,
  - hooks `session_shutdown`,
  - and adds an explicit stop command.
- The main-worktree docs explicitly treat richer future directions as follow-on work, especially:
  - structured goals,
  - diagnostics,
  - multi-candidate tactic branching,
  - and broader scaffold/knowledge integration.
- The current toolkit appears to have **no dedicated TypeScript test suite** in the repository.

### Pre-toolkit repository reference points

Primary rewrite docs and plans studied:

- `plan.md`
- `README.md`
- `docs/architecture.md`
- `docs/server/overview.md`
- `docs/server/protocol.md`
- `docs/knowledgebase/cli.md`
- `docs/informal/cli.md`
- `plans/knowledgebase.md` and `plans/knowledgebase/*.md`
- `plans/informal.md` and `plans/informal/*.md`
- `plans/server.md` and `plans/server/*.md`

Primary rewrite TypeScript/package files studied:

- `index.ts`
- `package.json`
- `tsconfig.json`
- `lakefile.lean`

Primary rewrite implementation files studied:

- `AFTK/Server/Main.lean`
- `AFTK/Server/Protocol.lean`
- `AFTK/KnowledgeBase/PathLayout.lean`
- `AFTK/KnowledgeBase/Cli/Main.lean`
- `AFTK/KnowledgeBase/Cli/Types.lean`
- `AFTK/KnowledgeBase/Cli/Render.lean`
- `AFTK/Informal/Cli/Main.lean`
- `AFTK/Informal/Cli/Types.lean`
- `AFTK/Informal/Cli/Render.lean`
- `AFTK/Informal/Tracking.lean`
- `AFTK/Informal/Dependencies.lean`
- `AFTK/Informal/Presentation.lean`

Key findings from the repository state before the toolkit landed:

- The first three layers are already implemented in Lean and documented.
- The server layer deliberately remains Lean-centric in v1:
  - `docs/server/protocol.md` preserves the current hub method family,
  - `docs/server/overview.md` confirms the current operational model,
  - and `plans/server/integration.md` explicitly rejects turning the server into a general-purpose lower-layer RPC mirror in v1.
- The rewrite knowledge-base layer already has a stable CLI with JSON and text output:
  - `lake exe aftk knowledgebase ...`
  - documented in `docs/knowledgebase/cli.md`.
- The rewrite informal layer already has a stable CLI with JSON and text output:
  - `lake exe aftk informal ...`
  - documented in `docs/informal/cli.md`.
- The two lower-layer CLIs do **not** expose identical output conventions today:
  - the knowledge-base CLI uses a stable envelope-oriented JSON style,
  - while the informal CLI currently uses command-shaped JSON.
- At the time of the original research, there was **no actual toolkit implementation** yet:
  - the repository still had a Bun-style placeholder at the root,
  - `package.json` and `tsconfig.json` still reflected scaffold defaults rather than the final toolkit package shape,
  - and `docs/architecture.md` still marked the toolkit layer as not implemented.
- `lakefile.lean` defines the lower-layer executables the toolkit targets:
  - `aftk`
  - `aftk_server`
  - `aftk_file_worker`
- `AFTK/Server/Main.lean` currently accepts no CLI flags, always speaks over stdio, and drains remaining sessions on exit.
- `AFTK/KnowledgeBase/PathLayout.resolveRootPath` resolves relative roots against the process working directory, so toolkit child-process `cwd` choice directly affects default knowledge-base and informal-root behavior when `--root` is omitted.
- `AFTK/KnowledgeBase/Cli/Render.lean` currently emits exact dot-separated JSON command names such as:
  - `metadata.validate`
  - `validate.storage`
  - `search.text`
  - `relationships.related`
- `AFTK/Informal/Cli/Render.lean` success JSON is command-shaped around a `data` field and adds fields such as `modules`, `target`, `mode`, and `bodyMode` depending on the command.
- `AFTK/Informal/Tracking.lean`, `AFTK/Informal/Dependencies.lean`, and `AFTK/Informal/Presentation.lean` already sort declarations, references, dependency rows/leaves, tags, authors, relationship lines, and Lean-ref lines deterministically; rich `present` output also carries explicit body-preview truncation metadata.
- The pre-implementation TypeScript scaffold was Bun-flavored, while the main-worktree implementation and `pi` integration were Node-oriented.
  Resolving that mismatch was one of the key design decisions that led to the current Node-compatible toolkit runtime.

### Immediate architectural conclusion from the research

The rewrite toolkit should preserve the best parts of the main-worktree wrapper:

- reusable TypeScript library code below adapter surfaces,
- a managed hub client,
- compatibility with the existing Lean-facing tool family,
- and a thin pi integration wrapper.

But it should also go beyond that wrapper in two important ways:

1. it should be designed as a **real toolkit library**, not one large file built only around a single tool family; and
2. it should package not only the server layer, but also selected knowledge-base and informal capabilities exposed through the rewrite’s existing lower-layer interfaces.

## Core responsibilities

The toolkit layer should eventually provide the following capabilities:

- manage access to the long-running `aftk_server` process from TypeScript
- expose a typed client for the rewrite server protocol
- expose Lean-facing tool definitions built on that client
- expose selected knowledge-base tools built on `lake exe aftk knowledgebase ...`
- expose selected informal tools built on `lake exe aftk informal ...`
- normalize lower-layer success/failure behavior into consistent toolkit-facing conventions
- provide a reusable integration surface for custom TypeScript sessions and `pi`
- keep process lifecycle, cancellation, timeouts, and cleanup explicit
- provide a foundation that the later AI-agent layer can consume directly without rebuilding these integrations itself

## Architectural commitments

As this layer is designed in detail, it should preserve the following commitments.

### 1. Reuse lower-layer public interfaces rather than reimplement lower-layer semantics

The toolkit should talk to the lower layers through their public boundaries:

- server/file-worker: through the documented JSON-RPC protocol
- knowledge base: through the documented CLI and its JSON/text outputs
- informal layer: through the documented CLI and its JSON/text outputs

It should not parse canonical knowledge-base files directly or recreate Lean/informal semantics in TypeScript.

### 2. Keep reusable toolkit code separate from `pi`-specific registration

The main-worktree split between shared tool implementation and a thin `pi` wrapper is correct in spirit and should be preserved.

The rewrite toolkit should therefore distinguish at least between:

- reusable TypeScript runtime/client/tool code, and
- thin adapter code for `pi` or other host environments.

### 3. Preserve strong compatibility with the current Lean-facing tool family where that materially helps migration

The rewrite server protocol already preserves the current `open`/`hover`/`goals`/`tactic` method family.
The toolkit should likewise preserve the corresponding `aftk_*` Lean-facing tool family where practical.

This is especially important for:

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

### 4. Expand beyond the current server-only scope deliberately, not accidentally

The rewrite now has real knowledge-base and informal CLIs.
So the toolkit layer should not remain permanently frozen at “server wrapper only.”

However, expansion should be deliberate:

- selected high-value tool families first,
- not a blind mirror of every lower-layer command on day one,
- and not a hidden second protocol layer that obscures where semantics actually live.

### 5. Keep toolkit state minimal, derived, and operational

The toolkit may own operational state such as:

- a managed hub child process,
- pending requests,
- request timeout bookkeeping,
- per-session adapter objects,
- and transient formatting or truncation helpers.

It should not own canonical project state.

### 6. Treat structured details as the stronger compatibility contract than human text

The main-worktree toolkit already returns both:

- human-readable text content, and
- structured `details`.

AFTK should preserve this pattern and strengthen it.
Text should stay concise and helpful, but the more important machine-facing contract should be the structured detail payloads and typed error information.

### 7. Keep outputs bounded and explicit

The toolkit is being built for agent workflows.
So it should preserve and generalize the bounded-output discipline already visible in the main-worktree toolkit:

- truncation where needed,
- explicit indication that truncation happened,
- deterministic field selection where possible,
- and no accidental unbounded dumps of lower-layer output.

### 8. Keep process lifecycle behavior conservative and testable

The main-worktree toolkit’s startup/shutdown discipline is worth preserving in spirit.
AFTK should likewise make explicit decisions about:

- lazy versus eager hub startup,
- child-process ownership,
- graceful shutdown,
- forced termination fallback,
- timeout policy,
- and cancellation behavior.

### 9. Prefer Node-compatible TypeScript runtime assumptions

The rewrite’s current TypeScript placeholder files come from a Bun-style scaffold, but the actual integration target is much closer to Node:

- `child_process.spawn`
- stdio pipes
- `AbortSignal`
- `pi` integration

So the toolkit should target ordinary Node-compatible TypeScript behavior unless a later component doc gives a compelling reason to require something else.

### 10. Test real subprocess behavior, not only pure helpers

This layer exists to manage real lower-layer processes and real CLI/protocol boundaries.
So it needs tests that exercise:

- `lake exe aftk_server`
- `lake exe aftk knowledgebase ...`
- `lake exe aftk informal ...`

rather than depending only on mocked unit tests.

## Conceptual model

At a high level, the toolkit layer revolves around a small set of concepts:

- a **toolkit runtime context** that knows the project root, executable resolution policy, timeouts, and output policy
- a **managed hub client** for the rewrite server protocol
- a **CLI runner** for one-shot lower-layer commands
- a **tool family** built on one lower-layer interface
- a **normalized tool result** combining concise text with structured details
- a **host adapter** that mounts toolkit tools into `pi` or another TypeScript host
- **transient lower-layer handles** such as canonical file paths and tactic node ids that remain owned semantically by the lower layers

The toolkit layer’s main technical job is to unify three heterogeneous lower-layer interfaces:

1. a long-running JSON-RPC hub protocol,
2. a knowledge-base CLI with its own structured outputs and exit codes,
3. an informal CLI with a related but not identical output model.

The point of the toolkit is not to erase those differences entirely, but to make them manageable and explicit for higher-level code.

## Toolkit design-doc suite under `plans/toolkit/`

The toolkit component-plan suite now exists.
This overview file should therefore focus on cross-component priorities, sequencing, and phase gating, while the detailed behavior of each subsystem is governed by the component plans below.

| Design doc | Primary implementation responsibility | Phases it primarily governs |
| --- | --- | --- |
| `plans/toolkit/layout.md` | Source-tree shape, curated exports, module boundaries, `src/` migration, and the split between toolkit core and host adapters. | 0, 6, 7 |
| `plans/toolkit/runtime.md` | Runtime context construction, project-root discovery, executable resolution, subprocess helpers, timeout/cancellation policy, and shutdown/termination rules. | 1, 2, 4, 5 |
| `plans/toolkit/output.md` | Shared host-facing result envelope, normalized error/warning model, truncation policy, diagnostics policy, and shared render/truncation helpers. | 1, 3, 4, 5, 6 |
| `plans/toolkit/server-client.md` | TypeScript mirror of `docs/server/protocol.md`, JSON-RPC client design, request tracking, result guards, protocol-failure handling, and hub lifecycle rules. | 2, 3 |
| `plans/toolkit/lean-tools.md` | Exact Lean-facing `aftk_*` tool surface, parameter schemas, path normalization, server-error presentation, and dedicated Lean-tools factory. | 3 |
| `plans/toolkit/knowledgebase-tools.md` | Selected `knowledgebase_*` v1 surface, CLI bridge behavior, JSON-envelope parsing, validation-report handling, naming policy, and knowledge-base-family renderers. | 4 |
| `plans/toolkit/informal-tools.md` | Full current `informal_*` v1 surface, command-shaped JSON parsing, `modules` / `root` handling, dependency/presentation semantics, and informal-family renderers. | 5 |
| `plans/toolkit/pi-integration.md` | Thin pi mounting strategy, extension-vs-SDK integration modes, stop-command/session-shutdown policy, and `src/hosts/pi/*` responsibilities. | 6 |
| `plans/toolkit/testing.md` | Toolkit-native test tree, support helpers, script workflow, synthetic process fixtures, and real subprocess coverage expectations. | 0, 1, 2, 3, 4, 5, 6, 7 |

Recommended implementation-reference order:

1. `layout.md`, `runtime.md`, and `output.md` as the shared foundation
2. `server-client.md` as the first lower-layer integration boundary
3. `lean-tools.md` for the main-worktree compatibility surface
4. `knowledgebase-tools.md` and `informal-tools.md` for the rewrite-specific expansion beyond the old server-only toolkit
5. `pi-integration.md` and `testing.md` as the mounting and hardening layers

Likely future component plans still include:

- `plans/toolkit/composite-tools.md` if we later add cross-layer compound helpers that combine multiple lower-layer calls but still fall short of full AI orchestration
- a structured-results addendum only if the server protocol grows significantly beyond the current text-heavy goal/hover surface

## Relationship to adjacent layers

### Knowledge base layer

The toolkit should treat the knowledge-base CLI and its documented JSON/text behavior as the authoritative boundary for TypeScript integration in v1.
It should not bypass the knowledge-base layer with ad hoc file parsing.

### Informal layer

The toolkit should treat the informal CLI as the authoritative direct TypeScript integration path for declaration/reference/dependency/presentation queries that are not already surfaced through the Lean-centric server protocol.

### Server and file-worker layer

The toolkit should treat the rewrite server protocol as the authoritative Lean-facing interactive interface.
It should not invent a second TypeScript-side interpretation of node ids, hover semantics, or stale-session behavior.

### AI autoformalization agent layer

The later AI-agent layer should use the toolkit as its default source of practical TypeScript-facing tools.
However, the top-level rewrite architecture already allows the AI layer to invoke lower-layer CLIs directly when that is genuinely the better fit.

So the relationship should be:

- toolkit first for common workflows and reusable tool families,
- direct CLI access still allowed for unusual or expert flows,
- no requirement that the toolkit mirror every lower-layer command before the AI layer can begin.

## Boundaries and non-goals

The toolkit layer is important, but it still has a limited scope.

### In scope

- TypeScript runtime/process-management helpers for lower-layer integration
- a reusable server client and Lean-facing tool family
- selected knowledge-base and informal tool families
- result normalization and error mapping across lower-layer boundaries
- `pi` and custom-session integration surfaces
- TypeScript-side testing and hardening of these integrations

### Out of scope for this layer

- canonical knowledge-base storage or validation semantics themselves
- `informal[...]` elaboration semantics themselves
- server protocol redesign as a prerequisite for toolkit work
- AI-agent planning loops, ranking, or orchestration logic
- end-to-end autoformalization strategy selection
- remote service or multi-user deployment design
- background synchronization that silently mutates lower-layer state

Those belong to lower layers, the later AI layer, or future work.

## Design constraints

As the component plans are written, the toolkit layer should preserve the following constraints.

- keep dependencies one-directional: toolkit depends on lower layers, not vice versa
- do not duplicate canonical knowledge-base or informal content in toolkit-owned state
- preserve the explicit lower-layer boundaries instead of hiding them behind undocumented toolkit magic
- keep `pi`-specific integration thin and isolated
- prefer strong machine-readable details over scraping or depending on human text
- preserve main-worktree compatibility where it materially reduces migration cost
- do not blindly copy the current main-worktree one-file implementation wholesale; rewrite it with clearer module boundaries
- make timeouts, cancellation, truncation, and shutdown policy explicit in code and docs
- add real subprocess tests before declaring the layer stable
- continue following the rewrite policy of selective borrowing from `../aftk` rather than wholesale file copying

## Design clarifications resolved so far

The following overview-level design points are now considered settled enough to guide the component docs.

- The toolkit should be implemented as a reusable TypeScript library first, with thin host adapters on top.
- The Lean-facing `aftk_*` tool family should remain an important compatibility target for the rewrite.
- The toolkit should not wait for new first-class lower-layer server RPC methods before exposing rewrite knowledge-base and informal functionality; it should use the existing CLIs directly where appropriate.
- The initial toolkit should prioritize read/query/presentation flows outside the Lean server parity surface, rather than trying to mirror every mutation command from the lower layers immediately.
- Structured result payloads should be treated as the stronger compatibility contract than free-form text rendering.
- Lazy managed-hub startup remains a good default baseline unless the runtime design finds a compelling reason to change it.
- The toolkit should assume a Node-compatible runtime model unless later component work proves a different assumption is necessary.
- The earlier Bun-style placeholder package setup should be treated as scaffolding that was replaced, not as a lasting design signal.

## Remaining coordination work before implementation starts in earnest

The component-plan suite now answers most of the broad design questions.
The remaining plan-level work is narrower and mostly about keeping the first implementation disciplined.
The main coordination questions still worth resolving explicitly during implementation are:

- the exact public TypeScript names for the package’s top-level factories, option types, and cleanup handles
- whether toolkit families expose a host-agnostic internal tool-definition type first or directly expose pi-compatible `ToolDefinition` values from the start
- the exact package-script / loader combination for running the Node-native test suite (for example `tsx`-style execution)
- the exact aggregate-toolset composition surface once Lean, knowledge-base, and informal families all exist together
- whether any narrowly scoped composite helpers belong in the initial implementation or should wait for a later `composite-tools.md`

None of these questions block coding the baseline.
They are implementation-shaping questions, not architectural uncertainty about the layer’s role.

## Detailed phased implementation plan

Implementation should proceed bottom-up from shared runtime/process code to lower-layer clients, then to tool families, and only after that to host-specific adapters.
The main-worktree toolkit is still the best behavioral reference for the Lean-facing server surface, but AFTK must broaden beyond that server-only scope because the first three layers now already expose more than one public boundary.

### Phase dependency and landing overview

| Phase | Main outcome | Depends on | Should land before |
| --- | --- | --- | --- |
| 0 | Real TypeScript package skeleton replaces Bun placeholder scaffold | current repository only | 1–7 |
| 1 | Shared runtime + output foundation | 0 | 2–7 |
| 2 | Typed managed `aftk_server` client | 1 | 3, 6, 7 |
| 3 | Lean-facing `aftk_*` tool family | 2 | 6, 7 |
| 4 | Initial `knowledgebase_*` tool family | 1 | 6, 7 |
| 5 | Initial `informal_*` tool family | 1, 4 helpful but not strictly required | 6, 7 |
| 6 | Aggregate toolkit composition + pi adapters | 3, 4, 5 | 7 |
| 7 | Hardening, docs, and AI-layer handoff readiness | 0–6 | final baseline |

Recommended landing discipline:

- each phase should leave the repository buildable and typecheckable
- each new lower-layer boundary should receive at least minimal direct tests in the same phase that introduces it
- later phases may refine earlier helper names, but should not silently violate the component-plan contracts without updating those docs first

### Phase 0 — replace the placeholder scaffold with a real toolkit package skeleton

Objective:

- remove the accidental Bun-playground shape from the current repository
- create the filesystem and package structure that all later phases depend on
- make the library/core-vs-host split visible before behavior accumulates

Primary docs:

- `plans/toolkit/layout.md`
- `plans/toolkit/testing.md`
- `plans/toolkit/pi-integration.md`

Implementation work items:

1. **Source-tree migration**
   - create `src/index.ts` as the curated library root
   - create empty or skeletal module groups under:
     - `src/toolkit/runtime/`
     - `src/toolkit/output/`
     - `src/toolkit/server/`
     - `src/toolkit/knowledgebase/`
     - `src/toolkit/informal/`
     - `src/toolkit/tools/`
     - `src/hosts/pi/`
   - create `tests/toolkit/` plus the subdirectories settled in `plans/toolkit/testing.md`

2. **Package metadata migration**
   - replace the current Bun-oriented `package.json` scaffold with a Node-compatible ESM package shape
   - add explicit exports for at least:
     - `.` -> `src/index.ts`
     - `./pi` -> `src/hosts/pi/index.ts`
     - `./pi-extension` -> `src/hosts/pi/extension.ts`
   - add `pi.extensions` metadata pointing at the thin extension entrypoint
   - align dependencies with the actual toolkit plan rather than the current placeholder package

3. **TypeScript config migration**
   - replace Bun-oriented compiler defaults with Node-compatible settings that match the runtime plan
   - include both `src/**/*.ts` and `tests/toolkit/**/*.ts`
   - ensure the package typechecks with only skeleton modules in place

4. **Root-file cleanup**
   - remove the root placeholder `index.ts` from being the implementation home
   - if a temporary compatibility shim is briefly needed, keep it thin and explicitly transitional

5. **Initial workflow wiring**
   - add at least a `check` script and placeholder toolkit test scripts
   - ensure a contributor can discover the intended package entrypoints immediately from the repository tree

Phase-0 acceptance tests / checks:

- `tsc --noEmit` (or equivalent chosen typecheck command) succeeds on the new tree
- importing the package root and pi subpaths is structurally possible
- no new implementation logic is hiding in root-level placeholder files

Exit criteria:

- the repository clearly contains a real toolkit package layout
- `package.json` and `tsconfig.json` reflect deliberate runtime assumptions
- host adapters and tests have explicit homes, even if behavior remains skeletal

### Phase 1 — implement the shared runtime and output foundations

Objective:

- establish the shared machinery that every lower-layer integration and tool family will reuse
- make runtime/process behavior and result normalization explicit before any one family invents its own conventions

Primary docs:

- `plans/toolkit/runtime.md`
- `plans/toolkit/output.md`
- `plans/toolkit/testing.md`

Implementation work items:

1. **Runtime context and option resolution**
   - implement `src/toolkit/runtime/options.ts`
   - normalize `cwd`, explicit `projectRoot`, environment overrides, timeout policy, and capture policy into one resolved runtime context

2. **Project-root discovery**
   - implement `src/toolkit/runtime/project-root.ts`
   - follow the settled upward search for `lakefile.toml` / `lakefile.lean`
   - fail clearly if no project root is found instead of inheriting the main-worktree fallback to arbitrary cwd

3. **Executable resolution**
   - implement `src/toolkit/runtime/executables.ts`
   - represent explicit command specs for:
     - `lake exe aftk_server`
     - `lake exe aftk knowledgebase`
     - `lake exe aftk informal`
   - support per-spec overrides for tests and advanced integrations

4. **Runtime error model**
   - implement `src/toolkit/runtime/errors.ts`
   - cover configuration, spawn/start, process-result, timeout, cancellation, and lifecycle failures

5. **Subprocess helpers**
   - implement `src/toolkit/runtime/subprocess.ts`
   - provide both:
     - a managed-process helper for the long-running hub
     - a one-shot command helper for CLI families
   - implement bounded capture, abort handling, and conservative `SIGTERM`/`SIGKILL` escalation

6. **Shared CLI helper**
   - implement `src/toolkit/runtime/cli.ts`
   - provide a structured completed-command value that later client layers can interpret without re-running subprocess logic

7. **Output foundation**
   - implement:
     - `src/toolkit/output/result.ts`
     - `src/toolkit/output/truncate.ts`
     - `src/toolkit/output/render.ts`
   - define the normalized success/failure envelope
   - define normalized error kinds/categories and warning/diagnostic/truncation metadata
   - add shared truncation helpers and small shared text-building helpers

Phase-1 acceptance tests / checks:

- unit tests cover project-root discovery, command-spec resolution, timeout/cancellation, and normalized result builders
- synthetic process tests cover malformed output, stderr flood, timeout, and stubborn-child termination
- at least one minimal real smoke test proves the runtime helpers can invoke a real `lake exe ...` command successfully

Exit criteria:

- runtime/process behavior is centralized instead of duplicated
- one shared output contract exists for all later tool families
- no runtime module depends on `pi` or on any family-specific semantics

### Phase 2 — implement the typed rewrite server client

Objective:

- rebuild the strongest main-worktree capability first: a reusable managed client for `aftk_server`
- put JSON-RPC lifecycle and protocol validation below any tool-definition layer

Primary docs:

- `plans/toolkit/server-client.md`
- `plans/toolkit/runtime.md`
- `plans/toolkit/output.md`
- `docs/server/protocol.md`

Implementation work items:

1. **Protocol mirror**
   - implement `src/toolkit/server/protocol.ts`
   - define the method map for:
     - `open`
     - `close`
     - `load_node`
     - `get_hover`
     - `get_plain_goal`
     - `get_plain_term_goal`
     - `get_infoview`
     - `get_goals`
     - `run_tactic`
     - `run_tactic_steps`
     - `shutdown`
   - expose typed known server error codes corresponding to the current Lean definitions:
     - `-32001`
     - `-32010`
     - `-32011`
     - `-32012`
     - `-32013`
   - add lightweight method-aware result guards

2. **Managed client implementation**
   - implement `src/toolkit/server/client.ts`
   - build on the managed-process helper from Phase 1
   - implement newline-delimited JSON-RPC parsing, startup deduplication, pending-request tracking, and request timeout handling
   - treat malformed completed non-empty stdout lines as protocol failure rather than ignoring them

3. **Lifecycle surface**
   - expose:
     - `start()`
     - `isRunning()`
     - typed `request(...)`
     - named convenience methods
     - semantic `shutdown()`
     - lifecycle `stop(graceful?)`
   - preserve the useful main-worktree behavior that abort cancels local waiting but does not promise remote server-side cancellation

4. **Diagnostics behavior**
   - preserve recent stderr for protocol/runtime failures through the shared diagnostics model rather than blindly mirroring it to parent stderr

Phase-2 acceptance tests / checks:

- synthetic tests cover request correlation, timeout vs cancellation, malformed stdout, unknown ids, JSON-RPC error envelopes, and `shutdown()` vs `stop(...)`
- real integration tests exercise representative commands against `lake exe aftk_server`
- no tool definitions are needed yet for the client to be useful and testable

Exit criteria:

- the toolkit can talk to the rewrite hub reliably from TypeScript
- the server client has explicit protocol typing and validation
- lifecycle and error behavior are stable enough for the Lean tool family to consume directly

### Phase 3 — implement the Lean-facing `aftk_*` tool family

Objective:

- restore the practical, already-proven Lean-facing surface that agents in the main worktree relied on
- keep the public `aftk_*` namespace tied specifically to the server-backed Lean family

Primary docs:

- `plans/toolkit/lean-tools.md`
- `plans/toolkit/server-client.md`
- `plans/toolkit/output.md`
- `plans/toolkit/pi-integration.md`

Implementation work items:

1. **Dedicated Lean tools factory**
   - implement `src/toolkit/tools/lean.ts`
   - expose a dedicated family factory that returns the full current Lean-facing surface:
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

2. **Parameter schemas and normalization**
   - implement 1-based location validation
   - keep leading-`@` stripping in the tool layer, not in the server client or runtime layer
   - preserve node ids as opaque server-owned values

3. **Shared output usage**
   - map all success/failure cases into the shared result envelope
   - preserve raw server result payloads under `details.result`
   - attach `family: "lean"` and backend metadata `{ kind: "server", method }`

4. **Error presentation**
   - render known server codes more actionably while preserving exact code/data in structured details
   - keep no-auto-open semantics for file-scoped tools
   - keep `aftk_shutdown` as semantic shutdown plus owned-client cleanup

5. **Compatibility cross-check against the main worktree**
   - confirm the new family preserves the essential behavioral shape of `createAFTKTools(...)` for the Lean-facing surface
   - improve structure and validation without drifting on public tool names or basic expectations

Phase-3 acceptance tests / checks:

- fast tests assert the exact exported tool name set and parameter behavior
- representative real integration tests hit open/query/node/tactic/shutdown flows on real Lean fixtures
- no Lean tool requires the pi adapter in order to exist or be tested

Exit criteria:

- the rewrite once again has a usable Lean-facing TypeScript tool family
- the most important migration target from the main worktree is covered
- the family is reusable outside `pi`

### Phase 4 — implement the initial knowledge-base tool family

Objective:

- expose the already-implemented rewrite knowledge-base CLI through a disciplined TypeScript bridge
- start with the read/query/report commands that are immediately useful and already semantically stable

Primary docs:

- `plans/toolkit/knowledgebase-tools.md`
- `plans/toolkit/runtime.md`
- `plans/toolkit/output.md`
- `docs/knowledgebase/cli.md`

Implementation work items:

1. **Knowledge-base CLI client**
   - implement `src/toolkit/knowledgebase/client.ts`
   - build command constructors for the selected v1 read/query/report surface
   - always invoke the CLI in JSON mode by default
   - parse the envelope fields `command`, `root`, `ok`, `result` / `error`, and `warnings`
   - preserve exact dot-separated command identifiers such as `search.text`, `validate.storage`, and `relationships.related`

2. **Selected v1 tool surface**
   - implement `src/toolkit/tools/knowledgebase.ts`
   - expose exactly the currently chosen initial tools:
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

3. **Root and exit-code semantics**
   - expose optional `root` on every knowledge-base tool
   - preserve the lower-layer fact that omitted/relative roots resolve against child-process `cwd`
   - implement the special validation rule: exit code `4` plus a valid report remains a semantic success

4. **Normalization and rendering**
   - map knowledge-base results into `family: "knowledgebase"`
   - preserve warnings structurally
   - render concise text from structured result data instead of relaying lower-layer text output

5. **Explicit deferrals**
   - do not yet implement mutation wrappers for:
     - `init`
     - `create`
     - `rename`
     - `delete`
     - `body set`
     - `metadata replace`
   - do not quietly add toolkit-only query semantics beyond the lower-layer CLI

Phase-4 acceptance tests / checks:

- fast tests cover argv construction, envelope parsing, exact raw `command` preservation, and validation-report success-with-exit-4 handling
- real integration tests use checked-in knowledge-base fixtures and copied invalid roots where mutation is needed for testing
- results strongly assert normalized backend metadata, preserved exit codes, warnings, and actionable text

Exit criteria:

- the toolkit exposes a stable, query-first `knowledgebase_*` family
- the bridge is clearly CLI-based rather than file-parsing-based
- the validation/reporting behavior remains faithful to the lower layer

### Phase 5 — implement the initial informal tool family

Objective:

- expose the rewrite informal layer directly, rather than forcing all informal-facing usage through hover-like server surfaces
- preserve the actual split between environment-backed tracking/dependency queries and direct knowledge-base-backed presentation

Primary docs:

- `plans/toolkit/informal-tools.md`
- `plans/toolkit/runtime.md`
- `plans/toolkit/output.md`
- `docs/informal/cli.md`

Implementation work items:

1. **Informal CLI client**
   - implement `src/toolkit/informal/client.ts`
   - build command constructors for the full current repository informal CLI surface
   - parse command-shaped success JSON centered on `data`, with command-specific fields such as `modules`, `target`, `mode`, and `bodyMode`
   - parse structured failure JSON with `ok: false`, `error`, `command?`, and `format`

2. **Selected v1 tool surface**
   - implement `src/toolkit/tools/informal.ts`
   - expose the full current informal surface:
     - `informal_status`
     - `informal_decls`
     - `informal_decl`
     - `informal_refs`
     - `informal_ref`
     - `informal_deps`
     - `informal_present`

3. **Parameter and semantic rules**
   - require non-empty `modules` for environment-backed commands
   - keep `root` optional and presentation-specific for `informal_present`
   - preserve the `mode` / `body` rules for `informal_present`, including rejection of `body` with `mode: "compact"`
   - preserve the lower-layer distinction between `informal.notTracked` and other CLI failures in structured details

4. **Normalization and rendering**
   - map all results into `family: "informal"`
   - preserve deterministic ordering already provided by the lower layer instead of re-sorting arbitrarily in conflicting ways
   - preserve preview-body truncation metadata from the lower layer rather than inferring it only from rendered text

5. **Boundary discipline**
   - do not resurrect old `informalize_*` naming
   - do not add sidecar-management commands absent from the rewrite CLI
   - keep `informal_present` distinct from server-backed hover tools

Phase-5 acceptance tests / checks:

- fast tests cover repeated `--module` formation, command-shaped JSON parsing, exact lower-layer error-code preservation, and `present` parameter validation
- real integration tests use current informal fixture modules and knowledge-base fixture roots
- results assert deterministic ordering, structured payload preservation, preview truncation metadata, and stable normalized errors

Exit criteria:

- the toolkit exposes the full current informal query/presentation surface cleanly
- the informal family complements the Lean tools without blurring their responsibilities
- no TypeScript code is re-parsing Lean environments or knowledge-base files directly

### Phase 6 — implement aggregate toolkit composition and pi integration surfaces

Objective:

- compose the now-separate tool families into reusable host-facing bundles
- preserve the successful main-worktree architecture of shared toolkit logic plus a thin pi wrapper, while supporting both extension and direct SDK mounting

Primary docs:

- `plans/toolkit/pi-integration.md`
- `plans/toolkit/layout.md`
- `plans/toolkit/testing.md`
- `plans/toolkit/output.md`

Implementation work items:

1. **Aggregate toolkit composition**
   - implement `src/toolkit/tools/aggregate.ts`
   - provide family-selection and cleanup composition across:
     - managed Lean/server-backed tools
     - one-shot knowledge-base tools
     - one-shot informal tools
   - ensure cleanup is explicit and idempotent, even though only the managed hub meaningfully participates in shutdown

2. **Direct pi SDK helper**
   - implement `src/hosts/pi/index.ts` support for a direct SDK path such as `createPiToolkitCustomTools(options?)`
   - return pi-compatible custom tools plus an explicit `dispose()` handle

3. **Extension registration helper**
   - implement a registration helper such as `registerToolkitExtension(pi, options?)`
   - register the selected families
   - hook `session_shutdown`
   - register the explicit stop command
   - keep the stop command limited to toolkit cleanup rather than calling `ctx.shutdown()`

4. **Thin extension entrypoint**
   - implement `src/hosts/pi/extension.ts`
   - default to `cwd: process.cwd()` for project discovery anchoring
   - keep the file extremely small and declarative

5. **Package/distribution alignment**
   - make sure package exports and `pi.extensions` metadata match the actual implemented entrypoints
   - align dependency placement with current pi package guidance

Phase-6 acceptance tests / checks:

- adapter tests verify tool registration, family selection, stop-command behavior, and `session_shutdown` cleanup
- direct SDK helpers can be instantiated without the full extension runtime
- the adapter preserves tool names, descriptions, parameters, and result semantics from the underlying toolkit families

Exit criteria:

- the toolkit can be mounted both as a pi extension and as direct SDK custom tools
- the pi layer remains thin and host-specific rather than becoming the owner of semantics
- cleanup behavior is explicit, idempotent, and test-covered

### Phase 7 — harden tests, docs, and higher-layer handoff readiness

Objective:

- turn the baseline toolkit into a dependable substrate for the later AI layer
- make the repository honest about what is implemented, how it is tested, and what remains deferred

Primary docs:

- `plans/toolkit/testing.md`
- `plans/toolkit/output.md`
- all earlier toolkit component docs as needed
- `plan.md` and repository-facing docs when the toolkit becomes real enough to mention there concretely

Implementation work items:

1. **Finish the planned test matrix**
   - fill gaps in unit, synthetic, integration, and adapter coverage across all families
   - ensure the initial exact tool name sets and normalized result envelopes are asserted
   - keep real subprocess tests conservative and deterministic

2. **Workflow scripts and support helpers**
   - finalize package scripts for:
     - typecheck
     - toolkit unit tests
     - toolkit integration tests
     - combined full-stack workflow with `lake test`
   - finish support helpers under `tests/toolkit/support/`

3. **Repository documentation updates**
   - document the toolkit package entrypoints and intended host-integration surfaces
   - update toolkit-related overview docs if implementation reality has diverged from earlier placeholders
   - make it clear which commands/families are implemented versus intentionally deferred

4. **Plan-status and handoff updates**
   - update the status sections in `plans/toolkit.md` and the component docs honestly as phases complete
   - record any implementation-driven design change back into the relevant component doc
   - leave explicit notes for the later AI layer about which toolkit surfaces are the stable starting point

5. **Explicitly deferred follow-on work**
   - continue deferring knowledge-base mutation tools until the temp-copy mutation-test policy is actually implemented
   - continue deferring cross-layer composite tools and full AI orchestration concerns until the baseline toolkit is stable

Phase-7 acceptance tests / checks:

- the full intended toolkit workflow can be run through repository scripts
- documentation and code agree on the implemented public surface
- the later AI layer can consume the toolkit without requiring foundational runtime/process redesign

Exit criteria:

- the toolkit has realistic test coverage over every lower-layer boundary it depends on
- repository docs and plan statuses are honest and current
- the toolkit is stable enough to serve as the default TypeScript foundation for the AI autoformalization layer

## Cross-phase implementation rules

The phased plan above should be carried out under the following non-negotiable rules.

### 1. Library first, adapter second

If behavior exists only inside a `pi` extension wrapper, that is a design smell.
Core behavior should live in reusable toolkit modules first.

### 2. Preserve lower-layer ownership boundaries

The toolkit should not:

- parse canonical knowledge-base files directly,
- rederive informal semantics from source files,
- or reinterpret server-owned transient ids as if they were toolkit-owned state.

### 3. Normalize outputs deliberately, not by flattening away useful structure

The toolkit should present a consistent result contract, but it should still preserve lower-layer semantics and details where those details matter.

### 4. Start with selected high-value CLI-backed tool families, not total command mirroring

The rewrite lower layers already have broad CLI surfaces.
The toolkit does not need to mirror every command before it becomes useful.

### 5. Test each real boundary as it lands

- hub client changes should get real hub tests
- knowledge-base CLI bridges should get real CLI tests
- informal CLI bridges should get real CLI tests
- adapter lifecycle behavior should get direct tests where practical

### 6. Respect explicit deferrals

Until the baseline is stable, the implementation should continue to defer:

- knowledge-base mutation wrappers beyond the commands explicitly selected in the knowledge-base plan
- ad hoc cross-layer composite helpers that deserve their own design doc
- AI-orchestration logic that belongs to the later agent layer

### 7. Keep the plan suite synchronized with implementation

If coding uncovers a real mismatch between:

- this overview plan,
- a toolkit component plan,
- and the implementation reality,

then the relevant plan file should be updated in the same phase rather than letting the design-doc suite drift silently.

## Completion checklist for this plan

The toolkit layer overview in this file should count as implemented only when all of the following are true in the current repository:

- the placeholder root TypeScript setup has been replaced by a real toolkit package/module structure
- reusable runtime/process-management code exists below host adapters
- a typed rewrite server client exists and is tested
- the Lean-facing `aftk_*` tool family exists and is tested
- selected knowledge-base toolkit tools exist and are tested
- selected informal toolkit tools exist and are tested
- a thin `pi` integration wrapper exists over the reusable toolkit core
- result shaping, truncation, and error behavior are documented and tested
- the toolkit is clearly usable by the later AI-agent layer without requiring major foundational rework

Until then, the implementation status at the top of this file should remain “Not implemented” or be updated only to reflect partial completion honestly.

## Summary

The toolkit layer is the rewrite’s first TypeScript layer.
Its job is to convert the already-implemented Lean lower layers into practical, reusable, agent-facing TypeScript interfaces.

Research against the main worktree shows a valuable reference design:

- a managed hub client,
- a shared Lean-facing toolset,
- and a thin `pi` adapter.

Research against the current repository shows the necessary expansion:

- the server layer is now only one of several lower-layer boundaries,
- the knowledge-base and informal layers already expose real CLIs,
- and the original pre-implementation repository state had no toolkit implementation beyond placeholders.

So the rewrite toolkit should preserve the useful main-worktree Lean-tool surface while growing into a broader, well-factored TypeScript library that:

- wraps the rewrite server cleanly,
- exposes selected knowledge-base and informal tool families,
- keeps `pi` integration thin,
- normalizes outputs and errors coherently,
- and gives the later AI autoformalization layer a stable foundation to build on.
