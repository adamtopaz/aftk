# Server / file-worker overview

The server layer is the operational Lean service layer of the rewrite.
It exposes long-running JSON-RPC processes for file-oriented Lean queries and transient tactic exploration.

Public entrypoints:

- library roots: `import AFTK.Server`, `import AFTK.FileWorker`
- executables: `lake exe aftk_server`, `lake exe aftk_file_worker <path>`

For a component-by-component guide with direct code pointers, see `docs/server/library.md`.

## Architecture in one sentence

`aftk_server` is a hub that manages one `aftk_file_worker` process per open Lean file.

## What is implemented

The current server layer includes:

- shared protocol types in `AFTK.Server.Protocol`
- `lean_worker`-based JSON-RPC transport helpers in `AFTK.Server.Transport`
- hub/session management in `AFTK.Server.Hub`
- one-shot file snapshot construction in `AFTK.FileWorker.Context`
- source-position Lean queries in `AFTK.FileWorker.Queries`
- transient tactic-state capture and replay in `AFTK.FileWorker.TacticState`
- richer `informal[...]` hover integration in `AFTK.FileWorker.Informal`
- executable wrappers for the hub and worker
- direct worker tests, hub tests, integration tests, and subprocess end-to-end tests

## Executables

### `aftk_server`

Start the public hub:

```text
lake exe aftk_server
```

This process speaks newline-delimited JSON-RPC over stdio.
It is the entrypoint higher-level tools should talk to.

### `aftk_file_worker <path>`

Start a worker for one file:

```text
lake exe aftk_file_worker path/to/File.lean
```

In ordinary use you do not start workers manually.
The hub spawns them on demand.

## Hub model

The hub is intentionally operational and fairly thin.
It is responsible for:

- normalizing and canonicalizing file paths
- maintaining one session per open file
- spawning workers via `lake exe aftk_file_worker <path>`
- checking file freshness before forwarding requests
- detecting dead workers
- forwarding JSON-RPC requests to the correct worker
- invalidating/replacing stale workers
- implementing hub-level `run_tactic_steps`

It is **not** responsible for Lean semantic analysis itself.
That stays in the worker.

## Worker model

A file worker owns:

- one Lean file path
- one one-shot elaborated semantic snapshot of that file
- command/info-tree data for source-position queries
- a local store of transient tactic state nodes

The worker currently reads the file from disk once at startup and does not support incremental in-memory edits.
That is a deliberate v1 choice.

## File identity and invalidation

### Path identity

The hub tracks both:

- a normalized absolute path
- a canonical path when real-path resolution succeeds

Sessions are keyed by the canonical path, with normalized-path aliases preserved for lookup.

### File freshness

The hub stamps each open file by:

- modification time
- byte size

Before forwarding most requests, it compares the current stamp with the session stamp.
If the file changed, the session is invalidated and callers get a reopen-required error.

### Worker liveness

If a child process exits or becomes unavailable, the hub removes the session and surfaces a worker-unavailable error.

## Source-position model

All public source positions use **1-based** coordinates:

- `line >= 1`
- `col >= 1`

The worker converts them to Lean raw positions via the file map.
Invalid positions are reported as JSON-RPC invalid-params errors.

## Query surface

The current public hub methods are:

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

These are documented in detail in `docs/server/protocol.md`.

## Lean integration strategy

The worker uses a one-shot frontend path built from Lean APIs:

- `Parser.parseHeader`
- `Elab.processHeader`
- `Elab.IO.processCommands`

For positional queries it reuses Lean core info-tree utilities such as:

- hover lookup
- goal lookup
- term-goal lookup

So the current implementation stays close to Lean's existing editor/query machinery rather than reinventing position heuristics.

## Tactic-state model

`load_node` captures the tactic state(s) available at a source position and stores them as opaque node ids like:

- `node-0`
- `node-1`

These ids are:

- session-local
- file-local
- transient
- invalidated by reopen/restart

`run_tactic` runs one tactic from a stored node and returns:

- the resulting goals
- a fresh `nextId`

`run_tactic_steps` is implemented at the hub by repeatedly calling `run_tactic` under the same session lock.

## Informal-layer integration

The rewrite-specific integration point is richer hover for `informal[...]` sites.

Behavior today:

- ordinary Lean hover still works for ordinary syntax
- when the hovered syntax site is a recognized `informal[...]` term, the worker attempts to resolve the referenced node through `AFTK.Informal`
- on success, the worker returns rich preview-style presentation text
- on failure, it falls back to ordinary Lean hover behavior instead of failing the request

The worker reads the same `aftk.informal.root` option that ordinary informal elaboration uses.

## Practical example flow

A typical client session looks like this:

1. `open { path }`
2. `get_hover { path, line, col }` or another read-only query
3. `load_node { path, line, col }`
4. `get_goals { path, id }`
5. `run_tactic { path, id, tactic }`
6. `close { path }` or `shutdown {}`

## Important current limitations

- one-shot file snapshots only
- no incremental document updates
- no request cancellation layer beyond what the transport/library already provides
- no first-class server methods for generic knowledge-base operations
- no persistence of tactic exploration history

These are intentional current boundaries, not accidental omissions in the docs.

## Where to read next

- `docs/server/library.md`
- `docs/server/protocol.md`
- `docs/server/testing.md`
