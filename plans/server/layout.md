# Server/File-Worker Library Layout

## Status

Component plan and implementation-status document for the Lean module and executable layout of the server/file-worker layer.
This document refines the overall server-layer plan in `plans/server.md` and works together with `plans/server/transport.md`, `plans/server/protocol.md`, `plans/server/hub.md`, `plans/server/worker.md`, `plans/server/lean-integration.md`, `plans/server/integration.md`, and `plans/server/testing.md`.

## Component implementation status

- Overall status: Implemented
- Implemented in code: Yes
- Last updated basis: the repository now has the documented server/file-worker module tree, standalone executables, and server test-tree wiring.

## Purpose

This document defines how the server/file-worker layer should be laid out in the Lean source tree.
It is about:

- library/module structure
- executable entrypoint boundaries
- dependency direction between hub, worker, and shared modules
- and the matching test-tree layout

The goal is to let implementation start from a clear module tree rather than accumulating process management, protocol code, and Lean semantic logic in one or two oversized files.

## Design goals

The layout should:

- keep reusable library code separate from executable entrypoints
- keep shared protocol and transport concerns below both hub and worker implementations
- use `lean_worker` explicitly for transport/client/server plumbing without scattering its usage arbitrarily through unrelated modules
- keep hub operational logic separate from worker semantic logic
- leave an obvious home for lower-layer integration helpers
- align with the phased implementation plan in `plans/server.md`
- make process-level and direct-library testing straightforward
- fit naturally into the existing `AFTK` / `AFTKTest` structure of the repository

## Scope and non-scope

### In scope

- Lean module/file layout under `AFTK/Server/` and `AFTK/FileWorker/`
- library root modules and executable root modules
- recommended dependency direction between module groups
- test-tree layout under `AFTKTest/Server/`
- `lakefile.toml` executable targets for this layer

### Out of scope

- exact protocol JSON values
- exact transport framing internals
- exact test-case contents
- top-level CLI subcommand design for `lake exe aftk ...`

The important executable compatibility surface for this layer is the standalone pair:

- `lake exe aftk_server`
- `lake exe aftk_file_worker`

not a new umbrella `aftk server ...` subcommand in v1.

## Naming conventions

The intended naming conventions for this layer are:

- server namespace root: `AFTK.Server`
- worker namespace root: `AFTK.FileWorker`
- shared public protocol module: `AFTK.Server.Protocol`
- shared transport module: `AFTK.Server.Transport`
- public server executable root: `AFTK.Server.Main`
- public file-worker executable root: `AFTK.FileWorker.Main`

This preserves the useful distinction between:

- the hub/server role,
- and the per-file worker role.

## Layout principles

### 1. Keep shared protocol and transport below both hub and worker

The hub and worker both need to speak the same protocol and use the same transport boundary.
So shared protocol/transport code should live in shared modules, not inside one side’s private implementation tree.

### 2. Keep the hub small and operational

The hub module tree should primarily contain:

- session/lifecycle logic
- subprocess management
- request forwarding
- public handler wiring

It should not contain Lean semantic query code.

### 3. Keep the worker semantic code below worker handler wiring

The worker should separate:

- context construction
- source-position queries
- tactic-state capture/execution
- lower-layer-aware hover integration
- RPC handler wiring

This will matter when the worker grows richer over time.

### 4. Leave an explicit home for lower-layer integration helpers

Lower-layer-aware hover behavior should not be buried anonymously in a generic queries file if it becomes nontrivial.
A small dedicated worker-side integration helper module is justified from the start.

### 5. Keep executable roots thin

The executable root modules should mostly:

- parse command-line arguments
- construct transport endpoints
- initialize shared state
- launch the appropriate server loop

They should not contain the main implementation logic.

### 6. Keep tests parallel to implementation concerns

The test tree should make it easy to test:

- shared protocol/transport behavior
- worker semantics directly
- hub lifecycle behavior
- and end-to-end subprocess behavior

## Recommended initial module layout

A good initial layout for this layer is:

```text
AFTK.lean
AFTK/Server.lean
AFTK/Server/Protocol.lean
AFTK/Server/Transport.lean
AFTK/Server/Hub.lean
AFTK/Server/Main.lean
AFTK/FileWorker.lean
AFTK/FileWorker/Context.lean
AFTK/FileWorker/Queries.lean
AFTK/FileWorker/TacticState.lean
AFTK/FileWorker/Informal.lean
AFTK/FileWorker/Handlers.lean
AFTK/FileWorker/Main.lean
Main.lean
AFTKTest/Server.lean
AFTKTest/Server/Assert.lean
AFTKTest/Server/Fixtures.lean
AFTKTest/Server/Protocol.lean
AFTKTest/Server/Worker.lean
AFTKTest/Server/Hub.lean
AFTKTest/Server/Integration.lean
AFTKTest/Server/Process.lean
AFTKTest/Server/Main.lean
tests/server/fixtures/...
tests/server/golden/...
```

This is intentionally pragmatic rather than maximally granular.
It gives the layer clear homes without over-fragmenting the first implementation.

## Module responsibilities

## `AFTK/Server.lean`

This should be the curated public root for the server-side library surface.
It should re-export reusable server-facing modules such as:

- `AFTK.Server.Protocol`
- `AFTK.Server.Transport`
- `AFTK.Server.Hub`

It should not import executable-only modules.

## `AFTK/Server/Protocol.lean`

This should define:

- shared request/response types
- source-position and range types
- error-code constants/helpers
- JSON codec helpers for the settled protocol surface

Both the hub and worker should depend on this module.

## `AFTK/Server/Transport.lean`

This should define the AFTK-local integration layer over `lean_worker`, including things like:

- common helpers for constructing `lean_worker` client/server transports
- shared JSON/object-param helper utilities used by the hub and worker
- small local wrappers around the `lean_worker` request/response flow where that improves readability
- client request helpers for subprocess RPC
- graceful child-stop helpers

It should not own file-session state or Lean semantic logic, and it should not try to replace `lean_worker` with a second transport framework.

## `AFTK/Server/Hub.lean`

This should implement:

- file identity resolution
- file-stamp reading
- worker spawn/stop helpers
- session registry state
- per-session request serialization
- public handler implementations and forwarding logic

This is the main operational heart of the hub.

## `AFTK/Server/Main.lean`

This should be the executable root for:

```text
lake exe aftk_server
```

It should remain thin and mostly wire together:

- stdio transport construction
- mutable hub state initialization
- hub server loop startup
- final cleanup on exit

## `AFTK/FileWorker.lean`

This should be the curated public root for reusable worker-side modules.
It should typically re-export:

- `AFTK.FileWorker.Context`
- `AFTK.FileWorker.Queries`
- `AFTK.FileWorker.TacticState`
- `AFTK.FileWorker.Informal`
- `AFTK.FileWorker.Handlers`

It should not import the worker executable module.

## `AFTK/FileWorker/Context.lean`

This should own one-shot worker context construction, including:

- file reading
- Lean frontend processing
- command-tree capture
- position-conversion helpers shared by query code

## `AFTK/FileWorker/Queries.lean`

This should own generic Lean query logic such as:

- command filtering by position
- hover lookup
- plain-goal lookup
- term-goal lookup
- infoview aggregation
- `load_node` preparation that depends on query results

## `AFTK/FileWorker/TacticState.lean`

This should own:

- the transient node-store type
- node-id allocation helpers
- state capture from goal info
- `get_goals`
- `run_tactic`
- stale-node error handling

## `AFTK/FileWorker/Informal.lean`

This should hold worker-side lower-layer integration helpers, especially:

- detection of `informal[...]` syntax at a queried site
- richer informal hover rendering through `AFTK.Informal`
- fallback behavior back to ordinary Lean hover

Keeping this separate makes the lower-layer integration easy to find and evolve.

## `AFTK/FileWorker/Handlers.lean`

This should wire the worker’s shared protocol methods to the underlying context/query/tactic helpers.
It is the natural place for the worker’s handler registry and internal `shutdown` request.

## `AFTK/FileWorker/Main.lean`

This should be the executable root for:

```text
lake exe aftk_file_worker <path>
```

It should stay thin and mostly:

- validate arguments
- build the worker context
- initialize worker state
- construct stdio transport
- launch the worker loop

## Top-level roots and executable integration

## `AFTK.lean`

Once this layer exists, `AFTK.lean` should eventually re-export the reusable library roots:

- `AFTK.KnowledgeBase`
- `AFTK.Informal`
- `AFTK.Server`
- `AFTK.FileWorker`

It should not import executable-only modules.

## `Main.lean`

The existing umbrella executable currently dispatches only knowledge-base and informal CLI commands.
That can remain true in v1.
The server layer’s compatibility surface should come from dedicated executables rather than from new umbrella subcommands.

## Lake targets

The `lakefile.toml` layout should eventually declare the `lean_worker` dependency and include executable targets equivalent to:

```toml
[[lean_exe]]
name = "aftk_server"
root = "AFTK.Server.Main"
supportInterpreter = true

[[lean_exe]]
name = "aftk_file_worker"
root = "AFTK.FileWorker.Main"
supportInterpreter = true
```

The exact dependency declaration syntax should follow the package format already used by the project, but the design intent is explicit: this layer should depend on `lean_worker`.
The existing `aftk` and `aftk_test` targets should remain in place.

## Recommended dependency direction

The initial dependency direction should be:

- `AFTK.Server.Protocol` -> depends on Lean basics only
- `AFTK.Server.Transport` -> depends on `AFTK.Server.Protocol` and `lean_worker`
- `AFTK.Server.Hub` -> depends on `AFTK.Server.Protocol` and `AFTK.Server.Transport`
- `AFTK.FileWorker.Context` -> depends on Lean frontend/query APIs and lower layers only where needed
- `AFTK.FileWorker.Queries` -> depends on `Context` and `Protocol`
- `AFTK.FileWorker.TacticState` -> depends on `Context`/`Protocol`
- `AFTK.FileWorker.Informal` -> depends on `AFTK.Informal` and worker query/context helpers
- `AFTK.FileWorker.Handlers` -> depends on worker modules plus shared protocol/transport and `lean_worker` handler APIs as needed
- executable roots -> depend on their respective library modules and `lean_worker` runtime wiring as needed

Important negative rules:

- the knowledge-base layer must not depend on the server/file-worker layer
- the informal layer must not depend on the server/file-worker layer
- the hub should not depend on worker semantic internals beyond the shared protocol and transport boundary

## Test-tree layout

A practical initial test layout is:

```text
AFTKTest/Server.lean
AFTKTest/Server/Assert.lean
AFTKTest/Server/Fixtures.lean
AFTKTest/Server/Protocol.lean
AFTKTest/Server/Worker.lean
AFTKTest/Server/Hub.lean
AFTKTest/Server/Integration.lean
AFTKTest/Server/Process.lean
AFTKTest/Server/Main.lean
tests/server/fixtures/lean/...
tests/server/fixtures/knowledgebase/...
tests/server/golden/...
```

This mirrors the component split and gives room for both direct-library and subprocess tests.

## Why this layout is the right first step

This layout lets the rewrite grow in the same practical way the other layers already do:

- reusable library modules first,
- executable wrappers second,
- and tests alongside them.

It also makes later changes easier.
For example:

- if the transport grows more sophisticated, it already has a home
- if the worker gets a richer document backend, `Context` can split further
- if informal hover integration grows, `Informal.lean` can split without disturbing the rest of the worker

## Additional implementation findings from the current repository layout

The current main worktree and repository layouts give a few concrete constraints for implementation.

- In the main worktree, `../aftk/lakefile.lean` currently builds the server executables directly from single-file roots:
  - `aftk_server` uses root `AFTK.Server`
  - `aftk_file_worker` uses root `AFTK.FileWorker`
- That layout works, but it also means the current `AFTK/Server.lean` and `AFTK/FileWorker.lean` each mix protocol types, handlers, subprocess wiring, and executable entrypoint logic in one file. The rewrite should keep the documented split into library modules plus thin `Main` modules specifically to avoid recreating that compression.
- In the repository, `lakefile.toml` already uses:
  - `testDriver = "aftk_test"`
  - `root = "AFTKTest.Main"`
- The existing test suites are aggregated by extending `AFTKTest.Main`, not by creating separate standalone test drivers for each subsystem.
- `AFTK.lean` currently re-exports only `AFTK.KnowledgeBase` and `AFTK.Informal`, while `Main.lean` currently dispatches only the `knowledgebase` and `informal` CLI surfaces. That confirms the current repo state recorded elsewhere in these plans and reinforces the decision to add standalone `aftk_server` / `aftk_file_worker` executables rather than broadening the umbrella CLI immediately.

These concrete layout facts make the rewrite plan more explicit:

- split the old monolithic server/worker files into reusable library modules on purpose
- wire server tests into the existing `aftk_test` aggregation path
- and keep server executables separate from the current top-level CLI dispatch.

## Completion checklist for this plan

This component plan should count as implemented only when all of the following are true in the repository:

- the module tree above or an explicitly documented close equivalent exists
- reusable server and worker library roots exist separately from executable roots
- `lakefile.toml` contains dedicated `aftk_server` and `aftk_file_worker` targets
- the dependency direction follows the documented layering constraints
- the test tree under `AFTKTest/Server/` exists and is wired into `lake test`

## Summary

The server/file-worker layer should be laid out as two reusable library trees plus two thin executable entrypoints, with shared protocol/transport modules below both sides and a dedicated worker-side integration helper for lower-layer-aware hover behavior.
That structure is the right foundation for both implementation and testing.
