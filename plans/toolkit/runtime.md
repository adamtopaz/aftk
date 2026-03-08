# Toolkit Runtime and Process Model

## Status

Component plan and implementation-status document for the runtime assumptions and shared process-management layer of the toolkit.
This document refines the overall toolkit-layer plan in `plans/toolkit.md` and works together with `plans/toolkit/layout.md`, `plans/toolkit/server-client.md`, `plans/toolkit/lean-tools.md`, `plans/toolkit/knowledgebase-tools.md`, `plans/toolkit/informal-tools.md`, `plans/toolkit/pi-integration.md`, `plans/toolkit/output.md`, and `plans/toolkit/testing.md`.

## Component implementation status

- Overall status: Not implemented
- Implemented in code: No
- Last updated basis: research against the main-worktree managed hub implementation in `/home/dev/aftk/lambda/src/aftk-tools.ts`, plus the rewrite worktree’s documented and implemented lower-layer entrypoints in `docs/server/overview.md`, `docs/server/protocol.md`, `docs/knowledgebase/cli.md`, `docs/informal/cli.md`, `lakefile.toml`, `AFTK/Server/Main.lean`, `AFTK/KnowledgeBase/PathLayout.lean`, `AFTK/KnowledgeBase/Cli/Main.lean`, and `AFTK/Informal/Cli/Main.lean`

## Purpose

This document defines the shared runtime and process-management foundation of the toolkit layer.
It is about:

- runtime assumptions for the TypeScript toolkit
- project-root discovery and working-directory policy
- executable resolution for the rewrite’s lower-layer entrypoints
- shared child-process helpers for long-running and one-shot commands
- timeout and cancellation behavior
- startup and shutdown policy
- stderr/stdout capture policy
- and the runtime-level error model

The goal is to give the toolkit one coherent operational foundation instead of letting each later component invent its own subprocess, timeout, and path-resolution behavior.

## Design goals

The runtime layer should:

- target ordinary Node-compatible TypeScript behavior rather than Bun-specific runtime APIs
- make project-root and executable resolution explicit and testable
- support both kinds of lower-layer interaction the toolkit needs:
  - long-running managed processes for `aftk_server`
  - one-shot CLI commands for `aftk knowledgebase ...` and `aftk informal ...`
- provide shared timeout, cancellation, and termination helpers
- preserve the useful main-worktree lazy-start managed-hub behavior while factoring it more cleanly
- keep stdout/stderr capture bounded and suitable for later machine-facing error/reporting layers
- avoid ambient console logging from reusable toolkit code by default
- preserve enough configurability for tests and non-default host integrations
- stay lower-layer-neutral rather than hardcoding knowledge-base, informal, or `pi` semantics into the runtime itself

## Scope and non-scope

### In scope

- Node-compatible runtime assumptions
- runtime configuration objects and resolution
- project-root discovery
- executable command resolution
- child-process spawning and lifecycle helpers
- timeout and `AbortSignal` integration
- shutdown/termination escalation rules
- bounded process-output capture policy
- runtime-level error classes and metadata

### Out of scope

- exact JSON-RPC request/response typing for the server
- exact tool parameter/result schemas
- exact human-facing output rendering
- exact CLI command selection for knowledge-base and informal tool families
- host-specific `pi` registration behavior
- exact test-case contents

Those belong to companion design docs.

## Research basis and design consequences

This runtime plan is based on explicit research in both worktrees.

### Main-worktree runtime reference points

Primary file studied:

- `/home/dev/aftk/lambda/src/aftk-tools.ts`

Important runtime observations from that implementation:

- The current toolkit uses `node:child_process.spawn`, `node:fs`, and `node:path` directly.
- The current toolkit resolves a project root by walking upward for `lakefile.toml` or `lakefile.lean`.
- The current toolkit manages a long-running `lake exe aftk_server` child process.
- Hub startup is lazy: the first request starts the child if necessary.
- Hub requests are newline-delimited JSON-RPC over stdio.
- Pending requests are tracked by id with per-request timeouts.
- Default request timeout is `120_000ms`.
- Graceful hub shutdown tries an RPC `shutdown` request with timeout `5_000ms`.
- If the child does not exit, the current toolkit escalates to `SIGTERM` and then `SIGKILL`, currently with two `1_500ms` waits.
- The current toolkit uses `AbortSignal` only to cancel the local waiting promise; it does not have true server-side request cancellation.
- The current implementation also uses an internal `autoStart: false` request mode during graceful shutdown so that cleanup never restarts the hub just to shut it down again.
- The current toolkit writes hub stderr straight to the parent process’s stderr.
- If no project root is found, the current helper falls back to the original start directory rather than failing early.

Main consequences for the rewrite:

- the rewrite should preserve the good parts of this operational model:
  - Node-compatible subprocess management,
  - lazy managed hub startup,
  - explicit request timeouts,
  - graceful shutdown plus forced termination fallback,
  - and upward project-root discovery;
- but it should improve the design by:
  - factoring subprocess behavior into reusable runtime helpers,
  - making stderr capture more deliberate than unconditional passthrough,
  - distinguishing runtime errors more cleanly,
  - and making root/executable resolution more explicit.

### Rewrite-worktree runtime reference points

Files studied:

- `docs/server/overview.md`
- `docs/server/protocol.md`
- `docs/knowledgebase/cli.md`
- `docs/informal/cli.md`
- `package.json`
- `tsconfig.json`
- `lakefile.toml`
- `AFTK/Server/Main.lean`
- `AFTK/KnowledgeBase/PathLayout.lean`
- `AFTK/KnowledgeBase/Cli/Main.lean`
- `AFTK/Informal/Cli/Main.lean`
- `plans/toolkit.md`

Important runtime observations from the rewrite:

- `lakefile.toml` already defines the exact lower-layer executables the runtime must know how to start:
  - `aftk_server`
  - `aftk`
  - `aftk_file_worker`
- The server is a newline-delimited JSON-RPC process over stdio started as:
  - `lake exe aftk_server`
- `AFTK/Server/Main.lean` currently accepts no CLI flags, constructs its transport from stdio immediately, and drains remaining sessions on exit.
- The server remains a separate public long-running process above a per-file worker model.
- The public protocol has important operational error codes including:
  - `-32010` file not open
  - `-32011` file changed; reopen required
  - `-32012` worker unavailable
  - `-32013` stale or unknown node id
- The knowledge-base CLI is a one-shot command surface started as:
  - `lake exe aftk knowledgebase ...`
- `AFTK/KnowledgeBase/PathLayout.resolveRootPath` resolves omitted or relative knowledge-base roots against the command process working directory, so the toolkit runtime’s chosen child `cwd` directly determines the lower layer’s default-root behavior.
- The informal CLI is a one-shot command surface started as:
  - `lake exe aftk informal ...`
- `AFTK/Informal/Cli/Main.lean` makes the split between command classes operationally real:
  - environment-backed commands import modules with `loadExts := true`,
  - while `present` bypasses module import and resolves a knowledge-base root directly.
- Both CLIs support `--format json`, but they do not use the same JSON success shape.
- Both CLIs use documented exit codes for usage/not-found/validation/conflict-style outcomes.
- The current TypeScript scaffold in the rewrite still reflects Bun defaults rather than the actual Node-like process model the toolkit needs.
  Concretely, `package.json` still points `module` at the root `index.ts`, while `tsconfig.json` still uses Bun-style `module: "Preserve"` and `moduleResolution: "bundler"` defaults.

Main consequences for the rewrite:

- the runtime layer must support both managed-process and one-shot-command patterns cleanly;
- it must not assume that all lower-layer boundaries look like the server JSON-RPC protocol;
- it should carry command/exit/stdout/stderr metadata upward rather than flattening everything into plain strings too early;
- and it should adopt Node-compatible runtime assumptions explicitly, even if Bun remains usable as a package manager or convenience command runner.

## Core runtime decisions

The v1 runtime design should make the following decisions explicit.

### 1. Target a Node-compatible ESM runtime model

The toolkit runtime should be designed around ordinary Node-compatible TypeScript behavior.
That means relying on things like:

- `node:child_process`
- `node:fs`
- `node:path`
- `AbortController` / `AbortSignal`
- ordinary Promise-based async control flow

It should **not** depend on Bun-only runtime APIs.

This does **not** forbid using Bun as a package manager or a convenient way to invoke `tsc`.
It does mean the toolkit’s operational semantics should be valid in a normal Node environment and in `pi`-style integrations.

### 2. Resolve one shared runtime context before tool-family code runs

The toolkit should have one resolved runtime context object representing the operational assumptions for a toolkit instance.
Conceptually, it should include things like:

- anchor `cwd`
- resolved `projectRoot`
- resolved executable specs
- environment overrides
- timeout policy
- capture/debug policy

This prevents each tool family from independently deciding:

- where the project root is,
- which command to spawn,
- how long to wait,
- or how to kill a hung child.

### 3. Distinguish `cwd` from `projectRoot`

The runtime should make a clean distinction between:

- `cwd`: the caller-provided anchor directory used for discovery
- `projectRoot`: the resolved Lean project root used as the default working directory for lower-layer commands

The main-worktree toolkit already hints at this distinction by accepting `cwd` and deriving `projectRoot`.
The rewrite should make it explicit.

Recommended rule:

- if `projectRoot` is provided explicitly, use it
- otherwise search upward from `cwd ?? process.cwd()` for `lakefile.toml` or `lakefile.lean`

### 4. Fail clearly if no project root can be resolved

The rewrite should prefer an explicit configuration error over silently using an arbitrary directory when no Lean project root can be found.

So unlike the current main-worktree helper, the default runtime should:

- search upward for `lakefile.toml` or `lakefile.lean`
- if none is found and no explicit `projectRoot` was provided, throw a runtime configuration error

Reasoning:

- the toolkit’s default lower-layer commands are all `lake exe ...` commands tied to the project
- falling back silently to a random directory produces worse diagnostics later
- early failure makes misconfiguration and test mistakes much easier to reason about

If a future use case genuinely needs looser behavior, it should be added deliberately through explicit executable/root overrides rather than through silent fallback.

### 5. Resolve lower-layer entrypoints as explicit command specs

The runtime should represent each lower-layer entrypoint as a resolved command specification, not as ad hoc strings scattered through the code.

At minimum, the resolved runtime should know how to start:

- the managed hub server:
  - `lake exe aftk_server`
- the knowledge-base CLI base:
  - `lake exe aftk knowledgebase`
- the informal CLI base:
  - `lake exe aftk informal`

A command spec should conceptually include:

- executable command
- fixed leading args
- working directory
- inherited/overridden environment
- a human-readable label for diagnostics

This allows:

- straightforward testing overrides,
- better error messages,
- and one central place to change executable strategy later if needed.

### 6. Use `spawn`, not shell-oriented command execution

The runtime should use `child_process.spawn` for both managed and one-shot subprocesses.
It should avoid shell-oriented execution helpers such as:

- `exec`
- `execSync`
- shell string concatenation

Reasons:

- argument boundaries remain explicit
- stdout/stderr can be captured incrementally and bounded
- cancellation/termination is easier to manage
- shell quoting bugs are avoided

### 7. Provide two runtime subprocess abstractions, not one giant generic wrapper

The toolkit runtime should explicitly support two different subprocess patterns.

#### Managed process helper

For long-running processes such as `aftk_server`, the runtime should provide a helper that owns:

- lazy/eager start hooks
- child liveness checks
- stdio pipe setup
- stderr capture
- write/close/wait helpers
- graceful termination and forced-kill escalation

#### One-shot command helper

For CLI-style commands such as `aftk knowledgebase ...` and `aftk informal ...`, the runtime should provide a helper that owns:

- argument execution
- optional stdin input
- stdout/stderr capture
- exit-code reporting
- timeout/abort handling
- termination on timeout or cancellation

Trying to force both patterns into one oversized abstraction would make the runtime harder to understand.

### 8. Default to lazy managed-hub startup, but expose explicit start capability

The main-worktree toolkit’s lazy hub startup is a good default.
The rewrite should preserve that default behavior.

So the runtime foundation should support:

- lazy start by default for the managed hub process
- an explicit `start()` path for integrations or tests that want eager validation

This preserves a convenient default while keeping tests and host adapters free to validate process startup earlier if useful.

### 9. Treat timeout and cancellation as separate concerns

The runtime should distinguish:

- caller cancellation via `AbortSignal`
- operation timeout due to elapsed configured time

These should become different runtime error kinds.

That distinction matters because they imply different next actions:

- caller cancellation often means “the host stopped caring”
- timeout often means “the lower layer may be slow, wedged, or producing too much output”

### 10. Use local wait-cancellation where protocol cancellation does not exist

The runtime should support `AbortSignal` throughout, but it must be honest about what cancellation means.

For one-shot commands that the toolkit itself owns, cancellation should actively terminate the child process.
For in-flight requests on a managed JSON-RPC hub, the toolkit can currently cancel the local waiting promise and unregister local bookkeeping, but it cannot assume server-side cancellation unless the protocol later adds it.

So the v1 runtime model is:

- strong cancellation for one-shot CLI commands
- local-wait cancellation only for in-flight hub requests unless/until a protocol-level cancel method exists

### 11. Separate internal capture safety limits from user-facing output truncation

The runtime needs safety limits on captured process output.
But those limits are **not** the same thing as the user-facing truncation policy described in `plans/toolkit/output.md`.

The runtime should therefore distinguish between:

- internal capture limits, used to prevent runaway memory growth while still preserving enough output for parsing and diagnostics
- later display/result truncation, used to shape what tools show to callers

For example:

- one-shot CLI stdout used for JSON parsing should allow a reasonably generous internal cap
- stderr capture can use a bounded rolling buffer
- user-facing tool output can still be truncated much more aggressively later

### 12. Avoid ambient process stderr mirroring by default

The main-worktree toolkit currently forwards hub stderr directly to the parent stderr stream.
That is simple, but it is not the right default for a reusable library.

The rewrite runtime should instead:

- capture stderr in bounded form by default
- expose it for diagnostics and error reporting
- optionally support teeing stderr to a debug sink when explicitly requested

Core toolkit code should not print directly to the console or parent stderr unless a debug policy explicitly asks for it.

### 13. Use conservative shutdown escalation

The runtime should preserve the main-worktree spirit of conservative shutdown behavior:

1. ask the lower layer to stop gracefully when a graceful path exists
2. wait only a bounded time
3. escalate to process termination if needed
4. escalate further to forced kill if the process still does not exit

This is important both for host-session shutdown and for test reliability.

### 14. Carry structured runtime failure metadata upward

The runtime should not flatten failures into plain strings at the lowest layer.
Instead, it should preserve structured metadata such as:

- which command was being run
- which cwd was used
- which timeout fired
- exit code or signal
- captured stdout/stderr excerpts
- whether the failure happened during start, execution, or shutdown

The output and tool layers can later decide how to render that information.

## Runtime context model

A practical v1 runtime context should resolve options into one internal object.
The exact TypeScript names can still evolve, but conceptually it should contain at least the following.

### Base location fields

- `cwd`: absolute discovery anchor
- `projectRoot`: absolute resolved project root

### Executable specs

- `hub`: default command spec for `lake exe aftk_server`
- `knowledgebase`: default command spec for `lake exe aftk knowledgebase`
- `informal`: default command spec for `lake exe aftk informal`

### Environment and debug fields

- merged environment map
- optional debug/event sink
- optional stderr-tee behavior

### Timeout policy

A practical default policy should include at least:

- per-request or per-command default timeout
- graceful-shutdown RPC timeout
- terminate-wait duration after `SIGTERM`
- forced-kill wait duration after `SIGKILL`

### Capture policy

A practical capture policy should include at least:

- max stdout bytes for one-shot commands
- max stdin bytes if the runtime enforces one
- bounded stderr ring-buffer size
- text encoding policy, which should be UTF-8 in v1

This context should be created once and then shared by the server client, CLI bridges, and tool-family factories built above it.

## Project-root discovery policy

The runtime should centralize project-root discovery.
It should not let each client/tool family rediscover the project root differently.

### Discovery algorithm

Recommended default algorithm:

1. start from `projectRoot` if explicitly provided, otherwise from `cwd ?? process.cwd()`
2. resolve the starting directory to an absolute path
3. if `projectRoot` was provided, validate that it exists and is directory-like enough for command execution
4. otherwise walk upward looking for either:
   - `lakefile.toml`
   - `lakefile.lean`
5. on first match, use that directory as `projectRoot`
6. if no match is found, raise a configuration error

### Why use the Lean project root as command cwd

The default lower-layer commands are all `lake exe ...` commands.
Running them from the resolved Lean project root ensures that:

- Lake resolves the correct package
- relative paths are interpreted consistently
- tests and hosts do not accidentally depend on whatever their own current directory happened to be

### Relative-path policy

The runtime should resolve its own working directories and executable overrides to absolute paths early.
But it should **not** rewrite semantic file-path arguments that belong to higher layers.

For example:

- resolving `projectRoot` to an absolute path is runtime behavior
- stripping a leading `@` from a tool path is **not** runtime behavior; that belongs to tool-level input normalization

## Executable resolution policy

The runtime should treat executable resolution as an explicit configuration surface.

### Default command specs

The default command specs in v1 should conceptually be:

```text
hub:           lake exe aftk_server
knowledgebase: lake exe aftk knowledgebase
informal:      lake exe aftk informal
```

all executed with:

- `cwd = projectRoot`
- merged environment derived from `process.env` plus explicit overrides
- piped stdio

### Override policy

The runtime should support explicit overrides for tests and advanced integrations.
A practical policy is:

- callers may override each logical command spec independently
- overrides replace the command and fixed leading args explicitly
- relative override paths should be resolved against the runtime `cwd` or `projectRoot` consistently and documented in code

This allows tests to point at wrappers or special executables without patching internal code.

### Why command specs should remain lower-layer-specific

The runtime should not prematurely collapse everything into one generic “aftk executable resolver.”
The current lower-layer entrypoints are meaningfully distinct:

- one public standalone server executable
- two CLI subcommand families

Keeping their specs explicit makes diagnostics and tests clearer.

## Shared subprocess helper design

### Managed-process helper

A reusable managed-process helper should provide capabilities such as:

- `start()`
- `isRunning()`
- `write(data)` or equivalent stdin access
- `waitForExit(timeout?)`
- `stopGracefully(...)` via a caller-provided graceful action when relevant
- `terminate()`
- `getRecentStderr()`
- lifecycle-state inspection for debugging and tests

It should own:

- child handle storage
- start-in-progress deduplication
- exit/error event wiring
- stderr capture
- termination escalation

It should **not** own:

- JSON-RPC request ids
- method names
- protocol parsing
- tool-specific formatting

Those belong above it.

### One-shot command helper

A reusable one-shot command helper should return a structured completion value such as:

- command label/spec
- exit code
- signal, if any
- captured stdout
- captured stderr
- duration metadata
- whether timeout/abort termination was involved

This helper should support:

- optional stdin text or bytes
- timeout
- `AbortSignal`
- bounded output capture
- clear termination on timeout or abort

### Why the one-shot helper should not eagerly throw on non-zero exit

The knowledge-base and informal CLIs have documented domain-specific exit codes.
Those exit codes carry meaning that later client layers need to interpret.

So the lowest runtime layer should preserve the completed process result even when exit code is non-zero.
It may offer a convenience assertion helper for “success expected” cases, but the raw completion object should remain available.

That way:

- `3` can later become a structured not-found case where appropriate
- `4` can later become a validation-failure case where appropriate
- the runtime itself stays lower-layer-neutral

## Timeout policy

The runtime should make timeout policy explicit and shared.

### Default operation timeout

The main-worktree toolkit already uses a `120_000ms` default request timeout.
That is a good default baseline for the rewrite’s runtime as well.

So the runtime should begin with:

- default operation timeout: `120_000ms`

where “operation” means:

- a hub request by default
- a one-shot CLI command by default

Individual calls may still override it when needed.

### Shutdown timeouts

The main-worktree toolkit uses a shorter timeout for graceful shutdown requests.
The rewrite should preserve that pattern.

A good v1 baseline is:

- graceful shutdown request timeout: `5_000ms`
- wait after `SIGTERM`: short bounded grace period
- wait after `SIGKILL`: short bounded confirmation wait

The exact short grace values may remain implementation constants, but the overall escalation pattern should be fixed.

### Timeout behavior

On timeout:

- one-shot commands should be terminated by the runtime
- managed hub requests should reject with a timeout error and clean up their local pending-request bookkeeping
- if the managed hub process itself is unhealthy or exits as part of the event, later requests should reflect that separately

## Cancellation policy

The runtime should use `AbortSignal` as the standard cancellation mechanism.

### One-shot CLI commands

If a one-shot CLI command is aborted:

- the runtime should terminate the owned child process
- the returned promise should reject with a cancellation error
- captured partial stdout/stderr should remain available on the error object where practical

### Managed hub startup/shutdown waits

If startup or shutdown waiting is aborted:

- the runtime should stop waiting
- and should apply the settled ownership rule for the child process:
  - during startup, kill the just-spawned owned child if the toolkit initiated it and the start was aborted
  - during shutdown, continue best-effort cleanup if the toolkit still owns the child

### In-flight hub requests

For requests already sent over JSON-RPC:

- abort should cancel local waiting and unregister local pending bookkeeping
- it should not promise server-side cancellation

That limitation should be documented clearly in the server-client layer too.

## Stdio and capture policy

The runtime should be explicit about stdio behavior.

### General stdio rule

For toolkit-managed subprocesses, use:

- piped stdin
- piped stdout
- piped stderr

by default.

The toolkit core should own the streams it needs for protocol traffic, capture, and diagnostics.

### Managed hub stdout

Managed hub stdout is protocol traffic.
It should be consumed by the server-client layer through a line-oriented UTF-8 reader.
The runtime should not attempt to treat it as ordinary logging.

### Managed hub stderr

Managed hub stderr should be captured into a bounded rolling buffer for diagnostics.
An explicit debug configuration may additionally tee it to:

- parent stderr
- or a provided logger sink

But the default should remain capture-only.

### One-shot CLI stdout

One-shot CLI stdout should be captured as full text up to a generous internal safety cap.
That is necessary because:

- later client layers may need to parse JSON from stdout
- truncating before parsing would destroy machine-readable correctness

If stdout exceeds the runtime’s safety cap, that should be treated as a runtime failure rather than silently truncated JSON.

### One-shot CLI stderr

One-shot CLI stderr should also be captured in bounded form.
Unlike stdout, stderr usually serves diagnostics rather than structured payload parsing, so a rolling capture policy is acceptable.

### No implicit console logging

Reusable toolkit runtime code should not do things like:

- `console.log(...)`
- `console.error(...)`
- unconditional `process.stderr.write(...)`

unless a debug policy explicitly requests it.

## Shutdown and termination policy

The runtime should make child ownership and stop behavior explicit.

### Managed hub shutdown sequence

When the toolkit owns a managed hub process and is asked to shut it down gracefully, the expected sequence is:

1. if the process is not running, return successfully
2. if graceful shutdown is requested, ask the higher layer to send the hub `shutdown` request
3. wait up to the graceful shutdown timeout
4. if the child still runs, send `SIGTERM`
5. wait a short bounded period
6. if the child still runs, send `SIGKILL`
7. wait a short bounded confirmation period
8. clear owned-child state

The runtime helper should support this sequence generically, while the server-client layer provides the hub-specific graceful action.

### One-shot command termination sequence

When a one-shot CLI command times out or is aborted:

1. send `SIGTERM`
2. wait a short bounded period
3. if still alive, send `SIGKILL`
4. wait for exit confirmation or bounded timeout
5. surface a timeout or cancellation error with command metadata

### Unexpected exit policy

If a managed child exits unexpectedly:

- mark it no longer running
- clear owned-child state if appropriate
- notify higher layers so they can reject pending work
- preserve exit code/signal and recent stderr for diagnostics

The runtime should not try to silently respawn a managed hub behind the caller’s back.
Respawn policy belongs to the server-client or host layer if ever needed.

## Environment policy

The runtime should inherit `process.env` by default and allow explicit overrides.

Recommended merge rule:

- start from `process.env`
- merge explicit toolkit runtime `env` overrides on top
- use the merged environment for all toolkit-managed subprocesses unless a specific command spec overrides it deliberately

The runtime should avoid lower-layer-specific environment magic unless a later document justifies it.
In particular, knowledge-base and informal root selection should normally happen through documented CLI options rather than hidden environment variables.

## Runtime error model

The runtime should define a small, explicit family of shared error types.
The exact class names can still be refined, but the categories should be settled.

### 1. Configuration errors

Use for problems such as:

- no project root found
- invalid explicit project-root path
- malformed executable override configuration

These are caller/setup problems, not lower-layer failures.

### 2. Process-start errors

Use for failures such as:

- executable not found
- spawn failure
- missing stdio pipe setup
- child exits before successful startup completes

### 3. Process-exit / command-result errors

Use when a subprocess completed or died in a way that higher layers may need to inspect structurally, carrying fields such as:

- exit code
- signal
- stdout
- stderr
- command label

For one-shot CLIs, later layers may choose not to treat every non-zero exit as an exception.
The important point is that the runtime preserves the completion metadata.

### 4. Timeout errors

Use when a configured timeout expires.
These should carry operation/command identity and partial diagnostic output where available.

### 5. Cancellation errors

Use when an `AbortSignal` cancels a runtime operation.
These should remain distinct from timeouts.

### 6. Ownership/lifecycle errors

Use for invalid operations on toolkit-owned subprocess state when needed, such as trying to write to a managed process that is no longer running.

## Recommended runtime module responsibilities

Within the layout settled in `plans/toolkit/layout.md`, the runtime directory should likely be refined as follows.

### `src/toolkit/runtime/options.ts`

Own:

- runtime option types
- default policy constants
- option normalization into a resolved runtime context

### `src/toolkit/runtime/project-root.ts`

Own:

- upward search for `lakefile.toml` / `lakefile.lean`
- explicit project-root validation
- absolute-path normalization for runtime-owned directories

### `src/toolkit/runtime/executables.ts`

Own:

- command-spec types
- default command specs for hub/knowledgebase/informal entrypoints
- override resolution and diagnostic labeling

### `src/toolkit/runtime/errors.ts`

Own:

- shared runtime error classes
- helpers for serializable diagnostic metadata

### `src/toolkit/runtime/subprocess.ts`

Own:

- managed-process helper
- one-shot command helper
- bounded stderr/stdout capture machinery
- wait-for-exit helpers
- `SIGTERM` / `SIGKILL` escalation helpers

### `src/toolkit/runtime/cli.ts`

Own:

- convenience helpers for running one-shot CLI commands using the resolved runtime context
- common completed-command value shapes
- small helpers that later knowledge-base and informal clients can share

This module should not contain command-family semantics like “knowledgebase show” or “informal deps”.
Those belong in the dedicated client layers above it.

## Boundaries and anti-patterns

The runtime layer should explicitly avoid the following mistakes.

### 1. No Bun-only runtime APIs in core logic

Package-manager convenience is fine.
Runtime lock-in is not.

### 2. No silent fallback to arbitrary cwd when project discovery fails

That behavior hides configuration mistakes and delays useful diagnostics.

### 3. No shell-string command construction

Use structured command + args spawning.

### 4. No unconditional console/stderr noise from library code

Debug output should be opt-in.

### 5. No unbounded accumulation of subprocess output

Long-running or malformed child behavior should not be allowed to consume memory without bound.

### 6. No lower-layer semantic interpretation in the runtime itself

The runtime should not decide that exit code `3` means “not found” for every future client.
That mapping belongs in knowledge-base and informal client layers.

### 7. No hidden respawn policy for managed hub children

Unexpected child death should surface clearly.
Silent automatic recovery would make operational behavior harder to reason about.

## Initial implementation checklist for this runtime design

Before the runtime layer can be considered in place, the rewrite should reach at least this baseline:

- a resolved runtime-context constructor exists
- project-root discovery and validation exist as shared helpers
- default command specs exist for hub, knowledge-base CLI, and informal CLI
- shared one-shot command execution helper exists with timeout and abort support
- shared managed-process helper exists with start/stop/terminate support
- bounded stderr capture exists
- graceful shutdown plus forced-kill escalation is implemented generically
- runtime error classes exist for config/start/timeout/cancel/process-result failures
- no reusable runtime module depends on `pi`-specific APIs
- the runtime assumptions are testable independently of any one tool family

## Summary

The rewrite toolkit needs one shared runtime foundation for all later TypeScript components.
That foundation should be explicitly Node-compatible, centered on a resolved runtime context, and able to manage both:

- a lazy, long-running `aftk_server` subprocess
- and one-shot `lake exe aftk knowledgebase ...` / `lake exe aftk informal ...` subprocesses

It should preserve the best operational ideas from the main-worktree toolkit — especially lazy start, request timeouts, and conservative shutdown — while improving them with:

- clearer configuration errors,
- reusable command/process helpers,
- bounded capture instead of ambient logging,
- and a cleaner runtime error model.

That runtime layer is the operational base that the later server client, CLI bridges, tool families, and `pi` adapters should all share.
