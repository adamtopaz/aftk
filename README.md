# AFTK

AFTK provides two Lean JSON-RPC executables:

- `aftk_file_worker`: per-file tactic worker
- `aftk_server`: hub server that manages multiple file workers

## Build

```bash
lake build
```

Or build specific binaries:

```bash
lake build aftk_server aftk_file_worker
```

## Executables

## `aftk_file_worker`

Run directly on one Lean file:

```bash
lake exe aftk_file_worker <path-to-lean-file>
```

Methods exposed by the file worker:

- `load_node` `{ line, col } -> { id : Array String }`
- `get_goals` `{ id } -> { goals : List String }`
- `run_tactic` `{ id, tactic } -> { goals : List String, nextId : String }`

## `aftk_server`

Run the hub server:

```bash
lake exe aftk_server
```

The hub:

- opens files by spawning `aftk_file_worker` subprocesses
- routes file-scoped requests to the correct worker
- supports multiple open files at once
- stops a worker when its file changes on disk

## Transport / protocol

Both executables use newline-framed JSON-RPC 2.0 over stdin/stdout (one JSON message per line).

## Hub API (`aftk_server`)

### `open`
Params:

```json
{ "path": "..." }
```

Result:

```json
{ "path": "...", "opened": true }
```

- `opened = true`: a new worker was started
- `opened = false`: file was already open and reused

### `close`
Params:

```json
{ "path": "..." }
```

Result:

```json
{ "path": "...", "closed": true }
```

### `load_node`
Params:

```json
{ "path": "...", "line": 7, "col": 3 }
```

Result:

```json
{ "id": ["..."] }
```

### `get_goals`
Params:

```json
{ "path": "...", "id": "..." }
```

Result:

```json
{ "goals": ["..."] }
```

### `run_tactic`
Params:

```json
{ "path": "...", "id": "...", "tactic": "..." }
```

Result:

```json
{ "goals": ["..."], "nextId": "..." }
```

### `run_tactic_steps`
Runs multiple tactics starting at a given node id.

Params:

```json
{ "path": "...", "id": "...", "tactics": ["...", "..."] }
```

Result:

```json
{
  "results": [
    { "goals": ["..."], "nextId": "..." },
    { "goals": ["..."], "nextId": "..." }
  ]
}
```

Notes:

- tactics are applied in order
- each next step uses the previous step’s `nextId`
- internally this uses JSON-RPC batch calls to the file worker

### `shutdown`
Stops all active file workers managed by the hub.

Params:

```json
{}
```

Result:

```json
{ "stopped": 2 }
```

## Error behavior

Common hub errors:

- `-32010`: file is not open
- `-32011`: file changed on disk; reopen required
- `-32012`: worker unavailable

Worker errors (e.g. tactic parse/failure) are propagated as JSON-RPC errors.

## Typical flow

1. `open` file
2. `load_node` at a source position
3. call `get_goals` and/or `run_tactic` / `run_tactic_steps`
4. optionally `close` file
5. `shutdown` hub when done
