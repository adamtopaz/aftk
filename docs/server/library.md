# Server / file-worker implementation guide

This document is the component-level implementation map for the server layer.
It covers both halves of the runtime:

- the public hub in `AFTK.Server`
- the per-file worker in `AFTK.FileWorker`

## Public entrypoints and code roots

Main code pointers:

- umbrella re-export: `AFTK.lean`
- server public root: `AFTK/Server.lean`
- file-worker public root: `AFTK/FileWorker.lean`
- hub executable: `AFTK/Server/Main.lean`
- worker executable: `AFTK/FileWorker/Main.lean`

Public entrypoints:

```lean
import AFTK.Server
import AFTK.FileWorker
```

Executables:

```text
lake exe aftk_server
lake exe aftk_file_worker <path>
```

## Component map

| Component | Main code | Responsibility |
| --- | --- | --- |
| Server public root | `AFTK/Server.lean` | Re-exports hub-side reusable modules |
| File-worker public root | `AFTK/FileWorker.lean` | Re-exports worker-side reusable modules |
| Protocol | `AFTK/Server/Protocol.lean` | Shared JSON-RPC request/response types and error codes |
| Transport | `AFTK/Server/Transport.lean` | StdIO transports, child-process clients, transport helpers |
| Hub | `AFTK/Server/Hub.lean` | Session management, worker spawning, forwarding, invalidation |
| Hub main | `AFTK/Server/Main.lean` | `aftk_server` executable entrypoint |
| Worker context | `AFTK/FileWorker/Context.lean` | One-shot Lean file elaboration snapshot |
| Worker queries | `AFTK/FileWorker/Queries.lean` | Hover, goals, term goals, infoview from source positions |
| Worker tactic state | `AFTK/FileWorker/TacticState.lean` | Snapshot capture, transient node ids, tactic execution |
| Worker informal integration | `AFTK/FileWorker/Informal.lean` | Rich hover for `informal[...]` sites |
| Worker handlers | `AFTK/FileWorker/Handlers.lean` | Worker-side JSON-RPC handlers |
| Worker main | `AFTK/FileWorker/Main.lean` | `aftk_file_worker` executable entrypoint |

## Root and re-export surfaces

### `AFTK.lean`

Project-wide umbrella import.
It re-exports both the hub and worker library roots.

### `AFTK/Server.lean`

Thin public root that re-exports:

- `Protocol`
- `Transport`
- `Hub`

### `AFTK/FileWorker.lean`

Thin public root that re-exports:

- `Context`
- `Queries`
- `TacticState`
- `Informal`
- `Handlers`

These roots deliberately separate reusable code from executable wrappers.

## Hub-side component details

### `AFTK/Server/Protocol.lean`

This file defines the shared wire vocabulary used by both hub and worker.

Important request/response types:

- `OpenParam`, `OpenResult`
- `CloseParam`, `CloseResult`
- `FileLocationParam`, `WorkerLocationParam`
- `FileNodeParam`, `WorkerNodeParam`
- `RunTacticParam`, `WorkerRunTacticParam`
- `RunTacticStepsParam`
- `ShutdownParam`, `ShutdownResult`, `WorkerShutdownResult`
- `SourcePosition`, `SourceRange`
- `HoverResult`
- `PlainGoalResult`
- `PlainTermGoalResult`
- `InfoViewResult`
- `LoadNodeResult`
- `GetGoalsResult`
- `RunTacticResult`
- `RunTacticStepsResult`

Important error helpers:

- `invalidParamsError`
- `internalError`
- `tacticFailedError`
- `fileNotOpenError`
- `fileChangedError`
- `workerUnavailableError`
- `staleNodeError`

Implementation role:

- gives the whole server layer one typed protocol surface
- keeps hub↔client and hub↔worker contracts aligned
- centralizes AFTK-specific JSON-RPC error codes

This is the first file to read if you want to change the wire contract.

### `AFTK/Server/Transport.lean`

This file wraps the `lean_worker` transport/client utilities used by the server.

Key definitions and functions:

- `JsonTransport`
- `WorkerChild`
- `RpcClient`
- `objParams`
- `serverTransportFromStdio`
- `clientTransportFromChild`
- `clientFromChild`
- `requestJson`
- `decodeResult`
- `stopChildGracefully`
- `closeTransport`

Implementation role:

- creates newline-delimited JSON transports from stdio streams
- turns a spawned worker child process into a JSON-RPC client
- provides small helper functions for structured request params and clean shutdown

This component intentionally keeps transport mechanics out of `Hub.lean`.

### `AFTK/Server/Hub.lean`

This is the operational center of the public server.
It owns session lifecycle and request forwarding.

Important types:

- `FileIdentity`
- `FileStamp`
- `WorkerSession`
- `State`
- `Context`
- `HubM`

Important functions:

- `normalizePathIO`
- `resolveFileIdentityIO`
- `readFileStampIO`
- `sessionFileChanged`
- `sessionIsDead`
- `spawnWorkerProcess`
- `spawnSessionIO`
- `stopSessionIO`
- `drainSessions`
- `stopAllSessions`
- `openFileIO`
- `closeFileIO`
- `shutdownIO`
- `loadNodeIO`
- `getHoverIO`
- `getPlainGoalIO`
- `getPlainTermGoalIO`
- `getInfoViewIO`
- `getGoalsIO`
- `runTacticIO`
- `runTacticStepsIO`
- `server`

Implementation role:

- resolves normalized and canonical file identities
- keys sessions by canonical path, while preserving normalized-path aliases
- stamps files by modification time and byte size
- spawns workers with `lake exe aftk_file_worker <path>`
- forwards most methods to the appropriate worker
- invalidates sessions when files change on disk
- removes sessions when workers die
- implements `run_tactic_steps` at the hub level by repeated worker `run_tactic` calls

Important design boundary:

- the hub manages process/session correctness
- the worker owns Lean semantic analysis

### `AFTK/Server/Main.lean`

This file is the `aftk_server` executable entrypoint.

Implementation role:

- requires zero command-line arguments
- builds a stdio JSON transport
- allocates hub state
- runs `AFTK.Server.Hub.server`
- drains and stops remaining worker sessions on shutdown

If you want the real process bootstrap path, this is the file to read.

## Worker-side component details

### `AFTK/FileWorker/Context.lean`

This component builds the one-shot semantic snapshot for a single Lean file.

Important types:

- `CommandTree`
- `WorkerContext`

Important functions:

- `rootCommandStx?`
- `build`

Implementation role:

- reads the file from disk once
- creates a `Parser.InputContext`
- parses the header with `Parser.parseHeader`
- processes imports/options with `Elab.processHeader`
- elaborates commands with `Elab.IO.processCommands`
- stores the resulting environment, info trees, and root-command syntax trees

This snapshot is the basis for every position-based query in the worker.

### `AFTK/FileWorker/Queries.lean`

This component turns source positions into hover/goals/infoview data.

Key functions:

- `toPosition`
- `toRange`
- `rangeContainsHoverPos`
- `rawPosAt`
- `commandTreesAt`
- `parserDocAt?`
- `hoverInCommandAt?`
- `getHoverAt?`
- `goalsAtPosition`
- `getPlainGoalAt?`
- `getPlainTermGoalAt?`
- `getInfoViewAt`

Implementation role:

- converts public 1-based positions into Lean raw positions
- selects candidate command trees near that position
- reuses Lean info-tree utilities for ordinary hover/goal lookups
- prefers richer informal hover when applicable
- constructs bundled infoview-style results from the lower-level query functions

This file is the core of the worker's read-only semantic query surface.

### `AFTK/FileWorker/TacticState.lean`

This component captures transient tactic-state snapshots and executes tactics from them.

Important types:

- `StateNode`
- `State`

Important functions:

- `StateNode.runTacticM`
- `captureNode`
- `goalsOfNode`
- `runTacticOnNode`
- `freshId`
- `insertNode`
- `insertNodes`
- `getNode`
- `getGoals`
- `runTactic`

Implementation role:

- captures Lean core/meta/term/tactic state around a goal site
- stores session-local nodes under ids like `node-0`
- parses tactic text with Lean's tactic parser
- evaluates tactics against stored snapshots
- returns a fresh node id for the resulting state

This is the implementation behind `load_node`, `get_goals`, and `run_tactic`.

### `AFTK/FileWorker/Informal.lean`

This component is the rewrite-specific hover integration point.

Important definitions:

- `InformalSite`
- `configuredKnowledgeBaseRoot?`
- `informalSiteAt?`
- `richHoverAt?`

Implementation role:

- recognizes `informal[...]` syntax sites inside command trees
- extracts the raw reference text and source range
- reads the `aftk.informal.root` option from worker query options
- resolves the reference through `AFTK.Informal`
- renders preview-style rich presentation text for hover
- falls back to ordinary hover if resolution fails

This file is where the server layer actually reuses the informal + knowledge-base layers.

### `AFTK/FileWorker/Handlers.lean`

This file registers the worker's JSON-RPC handlers.

Important definitions:

- `RuntimeContext`
- `HandlerM`
- `handleGetHover`
- `handleGetPlainGoal`
- `handleGetPlainTermGoal`
- `handleGetInfoView`
- `handleLoadNode`
- `handleGetGoals`
- `handleRunTactic`
- `server`

Implementation role:

- validates that params objects exist
- converts public positions to raw positions using `Queries.rawPosAt`
- delegates hover/goal/infoview work to `Queries.lean`
- delegates tactic-state work to `TacticState.lean`
- installs the worker method table used by the hub

This is the best file to read if you want the worker's actual method registry.

### `AFTK/FileWorker/Main.lean`

This file is the `aftk_file_worker` executable entrypoint.

Implementation role:

- requires exactly one file path argument
- builds a `WorkerContext` snapshot for that file
- creates a stdio JSON transport
- allocates tactic-state storage
- runs the worker server loop

This is the worker bootstrap path the hub relies on.

## Actual request flow

### Hub startup flow

1. `lake exe aftk_server`
2. `AFTK/Server/Main.lean` creates the transport and hub state
3. `AFTK.Server.Hub.server` installs the public method table

### Open-file flow

1. client calls `open`
2. `Hub.openFileIO` resolves the file identity and stamp
3. `Hub.spawnWorkerProcess` starts `lake exe aftk_file_worker <path>` if needed
4. `Transport.clientFromChild` turns the child into a JSON-RPC client
5. the hub stores the resulting `WorkerSession`

### Query flow

1. client calls a file-scoped method like `get_hover`
2. `Hub.withFileSession` checks the session exists
3. `Hub.withCheckedSessionIO` verifies liveness and file freshness
4. the hub forwards the request to the worker
5. `FileWorker/Handlers.lean` dispatches to query/tactic-state code
6. the result is decoded back through `Protocol.lean`

### Tactic flow

1. client calls `load_node`
2. worker captures tactic snapshots via `TacticState.captureNode`
3. worker stores them as `node-*` ids
4. client calls `run_tactic`
5. worker parses and runs the tactic, stores the next snapshot, and returns `nextId`

## Good extension points

If you are extending the server layer, prefer these boundaries:

- wire-format changes: `Protocol.lean`
- transport/process helpers: `Transport.lean`
- session lifecycle/invalidation: `Hub.lean`
- file elaboration snapshot logic: `FileWorker/Context.lean`
- read-only position queries: `FileWorker/Queries.lean`
- tactic-state semantics: `FileWorker/TacticState.lean`
- richer informal hover behavior: `FileWorker/Informal.lean`
- worker method registration: `FileWorker/Handlers.lean`

## Related docs

- `docs/server/overview.md`
- `docs/server/protocol.md`
- `docs/server/testing.md`
