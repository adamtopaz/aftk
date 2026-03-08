# Toolkit Layer Plan

## Status

Overall plan for the fourth layer of the `aftk` rewrite.
This document is intentionally architectural and serves as the top-level plan for the toolkit layer.
Detailed subdesigns should live in component plan files under `plans/toolkit/`.

## Plan implementation status

- Overall status: Not implemented
- Fully implemented: No
- Last updated basis: research against the main-worktree toolkit implementation in `/home/dev/aftk/lambda/src/aftk-tools.ts` and `/home/dev/aftk/lambda/src/aftk-extension.ts`, the main-worktree docs in `/home/dev/aftk/docs/aftk/README.md`, `/home/dev/aftk/README.md`, and `/home/dev/aftk/docs/future/autoformalization-tools.md`, plus the current rewrite worktree’s implemented lower layers and planning/docs suite

This section is the single place for tracking whether the toolkit-layer plan has been fully implemented.
It should be updated whenever the implementation meaningfully changes.

A practical definition of fully implemented for this plan is:

- the rewrite worktree contains a real TypeScript toolkit package rather than the current placeholder `index.ts`
- the toolkit exposes reusable non-pi-specific library code for talking to the rewrite’s lower layers
- the Lean-facing tool family exists with strong compatibility to the current main-worktree `aftk_*` hub tools where that still makes sense
- the toolkit exposes at least an initial selected surface for the rewrite’s knowledge-base and informal layers rather than remaining server-only
- the pi-specific integration surface is a thin adapter over reusable toolkit code rather than the owner of the implementation
- process lifecycle, error behavior, output shaping, and lower-layer integration are covered by appropriate TypeScript tests
- the implementation and usage are documented clearly enough for the later AI-agent layer to build on them directly

## Purpose

The toolkit layer is the first TypeScript layer in the rewrite.
Its job is to turn the lower-layer services and CLIs into practical, agent-facing TypeScript interfaces.

In the rewrite, the lower layers now include:

- the knowledge-base layer,
- the informal layer,
- and the server/file-worker layer.

So the toolkit layer should not be understood as “just the old AFTK hub wrapper, rewritten in TypeScript.”
It should preserve the useful parts of that current wrapper while expanding to the broader layered architecture now present in this worktree.

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
It is the first place where the rewrite should deliberately package those lower-layer capabilities for everyday machine use.

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

- `/home/dev/aftk/lambda/src/aftk-tools.ts`
- `/home/dev/aftk/lambda/src/aftk-extension.ts`

Primary docs studied:

- `/home/dev/aftk/docs/aftk/README.md`
- `/home/dev/aftk/README.md`
- `/home/dev/aftk/docs/agent-playbook.md`
- `/home/dev/aftk/docs/future/autoformalization-tools.md`
- `/home/dev/aftk/package.json`
- `/home/dev/aftk/tsconfig.json`

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

### Rewrite-worktree reference points

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
- `lakefile.toml`

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

Key findings from the current rewrite worktree:

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
- There is currently **no actual toolkit implementation** in the rewrite:
  - `index.ts` is only `console.log("Hello via Bun!")`,
  - `package.json` still points `module` at that root file and only carries Bun-oriented scaffolding such as `@types/bun`,
  - `tsconfig.json` still uses Bun-style defaults such as `module: "Preserve"` and `moduleResolution: "bundler"`,
  - and `docs/architecture.md` explicitly marks the toolkit layer as not implemented.
- `lakefile.toml` already defines the lower-layer executables the toolkit will target:
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
- The current TypeScript placeholder setup is Bun-flavored, but the main-worktree implementation and `pi` integration are Node-oriented.
  This needs an explicit design decision rather than accidental drift.

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

The rewrite should preserve this pattern and strengthen it.
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
The rewrite should likewise make explicit decisions about:

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

## Design docs still needed under `plans/toolkit/`

This layer does not yet have its component design-doc suite.
Before implementation proceeds far, we should write the following design docs under `plans/toolkit/`.
This is the dedicated checklist of the toolkit-specific design documents that are still needed, together with the purpose of each one.

| Design doc | Purpose |
| --- | --- |
| `plans/toolkit/layout.md` | Define the TypeScript package/module layout, public exports, dependency boundaries, likely `src/toolkit/...` structure, top-level `index.ts` policy, and the split between reusable toolkit code and host adapters. |
| `plans/toolkit/runtime.md` | Define runtime assumptions and shared operational utilities: project-root discovery, executable resolution, child-process helpers, timeout/cancellation policy, lazy-vs-eager hub startup, and shutdown/termination rules. |
| `plans/toolkit/server-client.md` | Define the TypeScript mirror of the rewrite server protocol, including JSON-RPC client design, typed request/response helpers, error mapping, request tracking, and compatibility expectations with `docs/server/protocol.md`. |
| `plans/toolkit/lean-tools.md` | Define the Lean-facing tool family built on the server client: parameter schemas, `aftk_*` naming compatibility, path normalization rules, node-id handling, result formatting, and which main-worktree behaviors should be preserved or improved. |
| `plans/toolkit/knowledgebase-tools.md` | Define the selected knowledge-base tool surface for the rewrite: which `lake exe aftk knowledgebase ...` commands should receive TypeScript wrappers first, how JSON parsing should work, mutation-vs-query boundaries, naming conventions, and CLI exit-code/error mapping. |
| `plans/toolkit/informal-tools.md` | Define the selected informal tool surface for the rewrite: wrappers around `lake exe aftk informal ...`, module/root option handling, presentation/dependency query coverage, naming conventions, and normalization of the informal CLI’s command-shaped JSON into toolkit-friendly results. |
| `plans/toolkit/pi-integration.md` | Define how the reusable toolkit should be mounted into `pi` and custom `@mariozechner/pi-coding-agent` SDK sessions, including thin extension wrappers, session-shutdown hooks, optional stop commands, and the boundary between generic toolkit code and `pi`-specific code. |
| `plans/toolkit/output.md` | Define the cross-tool result contract: concise text, structured details, truncation behavior, error envelopes, stderr handling, and normalization of differences between server-backed and CLI-backed tool results. |
| `plans/toolkit/testing.md` | Define the toolkit-layer testing strategy: unit coverage for pure helpers, subprocess tests for hub/CLI integration, temporary-fixture policy for mutation commands, and how toolkit tests should fit into repository workflows. |

Recommended writing order:

1. `layout.md`
2. `runtime.md`
3. `server-client.md`
4. `output.md`
5. `lean-tools.md`
6. `knowledgebase-tools.md`
7. `informal-tools.md`
8. `pi-integration.md`
9. `testing.md`

Likely future component plans include:

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
- continue following the rewrite policy of selective borrowing from `/home/dev/aftk` rather than wholesale file copying

## Design clarifications resolved so far

The following overview-level design points are now considered settled enough to guide the component docs.

- The toolkit should be implemented as a reusable TypeScript library first, with thin host adapters on top.
- The Lean-facing `aftk_*` tool family should remain an important compatibility target for the rewrite.
- The toolkit should not wait for new first-class lower-layer server RPC methods before exposing rewrite knowledge-base and informal functionality; it should use the existing CLIs directly where appropriate.
- The initial toolkit should prioritize read/query/presentation flows outside the Lean server parity surface, rather than trying to mirror every mutation command from the lower layers immediately.
- Structured result payloads should be treated as the stronger compatibility contract than free-form text rendering.
- Lazy managed-hub startup remains a good default baseline unless the runtime design finds a compelling reason to change it.
- The toolkit should assume a Node-compatible runtime model unless later component work proves a different assumption is necessary.
- The current Bun-style placeholder package setup in this worktree should be treated as scaffolding to replace, not as a settled design signal.

## Remaining design work before implementation

Unlike the first three layers, this layer does not yet have any component design docs in the rewrite worktree.
So the next step is to turn the research summary above into the component docs listed under `plans/toolkit/`.

The biggest questions those component docs still need to settle are:

- the concrete TypeScript module layout and package/export policy
- the exact runtime assumptions and dependency set
- the exact boundary between shared runtime helpers, server client code, CLI bridge code, and `pi` adapters
- which knowledge-base commands should receive first-class toolkit tools in v1
- which informal commands should receive first-class toolkit tools in v1
- naming policy for new non-Lean tool families so they do not collide with the existing server-compatible `aftk_*` names
- the exact normalized output contract across server-backed and CLI-backed tools
- the toolkit-layer testing workflow and its relation to the existing Lean-focused `lake test` flow

The architecture itself is already clear enough to begin component design.
The remaining work is design refinement, not broad architectural discovery.

## Detailed phased implementation plan

Implementation should proceed bottom-up from shared runtime/process code to lower-layer clients and only then to host-specific adapter surfaces.
The key sequencing rules should be:

- build reusable library pieces before registering tools into `pi`
- preserve lower-layer contracts instead of smearing them together too early
- land the Lean-facing server-compatible surface first, because it is the strongest compatibility target from the main worktree
- then add selected knowledge-base and informal tool families on top of the already-implemented rewrite CLIs
- test each process boundary with real subprocesses before treating it as stable
- if implementation experience forces a real design change, update the relevant component doc before continuing

### Phase 0 — replace the placeholder TypeScript scaffold with a real toolkit skeleton

Purpose:

- create the structural homes this layer will use
- stop treating `index.ts` and the current placeholder package config as meaningful architecture
- establish the separation between reusable toolkit code and host-specific adapters

Primary component docs:

- `plans/toolkit/layout.md`
- `plans/toolkit/testing.md`

Concrete deliverables:

- replace the current placeholder `index.ts` with a thin public export layer or other explicitly settled equivalent
- update `package.json` from the current minimal placeholder toward the dependencies actually needed for the toolkit
- update `tsconfig.json` from the current Bun scaffold toward the settled toolkit runtime assumptions
- add the initial directory/module skeleton for the toolkit, likely under something like:
  - `src/toolkit/runtime/`
  - `src/toolkit/server/`
  - `src/toolkit/tools/`
  - `src/toolkit/pi/`
- add a place for toolkit tests under something like `tests/toolkit/` or a similarly explicit TypeScript test tree
- keep the package buildable/typecheckable with skeletal modules before significant behavior lands

Exit criteria:

- the worktree has a real toolkit module skeleton rather than a placeholder script
- the package/typecheck setup reflects deliberate runtime assumptions
- there is a dedicated place for toolkit tests and host adapters

### Phase 1 — implement shared runtime and process-management foundations

Purpose:

- centralize the operational helpers that every tool family will need
- avoid duplicating process, timeout, and output plumbing across server and CLI integrations

Primary component docs:

- `plans/toolkit/runtime.md`
- `plans/toolkit/output.md`

Concrete deliverables:

- implement project-root discovery and override handling
- implement executable resolution policy for:
  - `lake exe aftk_server`
  - `lake exe aftk knowledgebase ...`
  - `lake exe aftk informal ...`
- implement shared child-process helpers for:
  - long-running managed processes
  - one-shot CLI commands
- implement timeout and cancellation helpers using standard TypeScript/Node primitives
- implement shared stderr capture policy and bounded stdout/stderr rendering
- implement common error types for runtime failures, lower-layer failures, and cancellation/timeout cases
- implement shared truncation/result-formatting helpers so later tool families do not invent incompatible local conventions

Exit criteria:

- the toolkit has a reusable operational foundation for both hub and CLI integrations
- timeout/cancellation/shutdown policy is explicit in code
- output/error shaping has one shared home rather than being scattered across tool families

### Phase 2 — implement the typed rewrite server client

Purpose:

- recreate the most valuable main-worktree toolkit capability against the rewrite server
- provide the reusable Lean-facing integration layer that later tool definitions can simply consume

Primary component docs:

- `plans/toolkit/server-client.md`
- `plans/toolkit/runtime.md`
- `plans/toolkit/output.md`

Concrete deliverables:

- define TypeScript-side protocol types matching `docs/server/protocol.md`
- implement newline-delimited JSON-RPC request/response handling over stdio
- implement lazy managed startup of `lake exe aftk_server`
- implement pending-request tracking keyed by request id
- preserve typed error information, especially server-family error codes such as:
  - `-32010`
  - `-32011`
  - `-32012`
  - `-32013`
- implement graceful shutdown plus forced termination fallback
- expose a reusable client API that host adapters and tool factories can use directly

Recommended implementation note:

The main-worktree `AftkHubClient` is a strong reference point for lifecycle behavior, but the rewrite should factor that logic into clearer modules rather than reproducing one large file verbatim.

Exit criteria:

- the rewrite toolkit can talk to the rewrite `aftk_server` reliably from TypeScript
- the managed hub lifecycle is explicit and testable
- typed request/response and error behavior exist below any tool-definition layer

### Phase 3 — implement the Lean-facing tool family on top of the server client

Purpose:

- reach practical parity with the main-worktree agent-facing Lean tools
- preserve the already valuable `aftk_*` surface while targeting the rewrite server implementation

Primary component docs:

- `plans/toolkit/lean-tools.md`
- `plans/toolkit/server-client.md`
- `plans/toolkit/output.md`
- `plans/toolkit/pi-integration.md`

Concrete deliverables:

- implement tool definitions for the Lean-facing server family:
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
- define parameter schemas and result-formatting policy for each tool
- preserve path normalization rules that are still useful in `pi`-style usage
- preserve the distinction between concise text content and structured details
- expose a shared `create...Tools(...)`-style factory for this Lean tool family, even before the `pi` wrapper is finalized

Exit criteria:

- the rewrite has a practical Lean-facing TypeScript tool surface again
- the most important migration target from the main worktree is covered
- the Lean-facing toolkit no longer depends on host-specific wrapper code for its core behavior

### Phase 4 — add selected knowledge-base toolkit tools

Purpose:

- make the rewrite toolkit aware of the actual knowledge-base layer that now exists below it
- expose high-value knowledge-base capabilities through TypeScript without waiting for AI-layer orchestration work

Primary component docs:

- `plans/toolkit/knowledgebase-tools.md`
- `plans/toolkit/runtime.md`
- `plans/toolkit/output.md`

Concrete deliverables:

- implement a reusable CLI bridge for `lake exe aftk knowledgebase ...`
- parse successful JSON output and map exit codes/failures into toolkit error/result conventions
- start with selected high-value commands, likely from the read/query/discovery family, such as:
  - status/probe operations
  - node listing/showing
  - search/relationship queries
  - validation/reporting where that materially helps agent workflows
- consider mutation wrappers only after the read/query bridge and output/error model are stable
- make naming conventions explicit so knowledge-base tool names do not conflict with the Lean-facing `aftk_*` server family

Exit criteria:

- the toolkit exposes an initial practical knowledge-base tool family
- those tools are clearly built on the existing CLI rather than on hidden file parsing
- JSON output and exit-code behavior are normalized into stable TypeScript-facing results

### Phase 5 — add selected informal toolkit tools

Purpose:

- expose the rewrite’s direct informal-layer query/presentation functionality at the toolkit level
- complement the server’s Lean-centric informal hover integration with explicit informal-layer query tools

Primary component docs:

- `plans/toolkit/informal-tools.md`
- `plans/toolkit/runtime.md`
- `plans/toolkit/output.md`

Concrete deliverables:

- implement a reusable CLI bridge for `lake exe aftk informal ...`
- normalize its command-shaped JSON outputs into toolkit-facing result shapes
- start with selected high-value commands, likely including:
  - status/summary queries
  - declaration/reference queries
  - dependency queries
  - direct presentation queries
- make module-loading and `--root` handling explicit in the toolkit-facing API
- preserve the informal layer’s meaning rather than turning it into an ad hoc agent-only abstraction

Exit criteria:

- the toolkit exposes an initial practical informal tool family
- the toolkit now spans all three lower layers in a coherent but still explicit way
- the informal tool family complements, rather than duplicates confusingly, the Lean-hover integration already available through the server layer

### Phase 6 — implement host adapters and integration surfaces

Purpose:

- mount the reusable toolkit into actual host environments without making those hosts the owner of the implementation
- preserve the main-worktree “shared toolset + thin `pi` wrapper” architecture in a broader rewrite-compatible form

Primary component docs:

- `plans/toolkit/pi-integration.md`
- `plans/toolkit/layout.md`
- `plans/toolkit/testing.md`

Concrete deliverables:

- implement a thin `pi` extension wrapper over the reusable toolkit code
- add explicit session-shutdown cleanup hooks
- decide whether to preserve an explicit stop command analogous to the main-worktree extension stop command
- expose integration helpers for custom `@mariozechner/pi-coding-agent` SDK sessions that do not depend on the full upstream `pi` extension mechanism
- document the intended integration points for the later AI-agent layer

Exit criteria:

- the reusable toolkit can be mounted cleanly into `pi` and custom sessions
- host adapters remain thin and operational rather than becoming the canonical implementation home

### Phase 7 — harden testing, docs, and higher-layer readiness

Purpose:

- make the toolkit safe for reuse by the later AI-agent layer
- turn the toolkit’s operational guarantees into tested repository behavior

Primary component docs:

- `plans/toolkit/testing.md`
- `plans/toolkit/output.md`
- all earlier component docs as needed

Concrete deliverables:

- add unit tests for pure helpers such as result shaping, truncation, and normalization utilities
- add subprocess tests for the real rewrite `aftk_server`
- add subprocess tests for real `lake exe aftk knowledgebase ...` and `lake exe aftk informal ...` commands against fixtures and temporary mutable copies where needed
- add integration tests for host adapters where practical
- update repository docs so the toolkit layer has the same implementation/documentation honesty as the first three layers
- update `plans/toolkit.md` implementation status when the baseline is genuinely landed

Exit criteria:

- the toolkit has realistic TypeScript test coverage over the actual lower-layer boundaries it depends on
- the later AI-agent layer can treat the toolkit as a stable foundation rather than as an experiment

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

## Completion checklist for this plan

The toolkit layer overview in this file should count as implemented only when all of the following are true in the rewrite worktree:

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

Research against the current rewrite shows the necessary expansion:

- the server layer is now only one of several lower-layer boundaries,
- the knowledge-base and informal layers already expose real CLIs,
- and the worktree currently has no toolkit implementation at all beyond placeholders.

So the rewrite toolkit should preserve the useful main-worktree Lean-tool surface while growing into a broader, well-factored TypeScript library that:

- wraps the rewrite server cleanly,
- exposes selected knowledge-base and informal tool families,
- keeps `pi` integration thin,
- normalizes outputs and errors coherently,
- and gives the later AI autoformalization layer a stable foundation to build on.
