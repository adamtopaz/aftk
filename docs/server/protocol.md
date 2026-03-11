# Server protocol reference

This document describes the public JSON-RPC method family implemented by `aftk_server`.

Transport details:

- JSON-RPC 2.0
- newline-delimited UTF-8 JSON messages over stdio
- one request per line
- object-shaped `params`

The hub speaks this protocol publicly. File-oriented Lean queries are forwarded to per-file workers; knowledge-base and informal methods run directly in the hub process.

## Start the server

```text
lake exe aftk_server
```

## Public methods

### `open`

Open or reuse a worker session for a file.

Request params:

```json
{ "path": "/abs/or/relative/File.lean" }
```

Result shape:

```json
{
  "path": "/canonical/path/to/File.lean",
  "opened": true
}
```

Semantics:

- `opened = true` means a new worker was spawned
- `opened = false` means an existing fresh session was reused
- the response path is the canonical session path used by the hub

### `close`

Close a file session if it exists.

Request params:

```json
{ "path": "/abs/or/relative/File.lean" }
```

Result shape:

```json
{
  "path": "/canonical/path/to/File.lean",
  "closed": true
}
```

Semantics:

- `closed = true` means an active session was stopped
- `closed = false` means no open session matched that path

### `load_node`

Capture tactic-state nodes at a source position.

Request params:

```json
{ "path": "/path/to/File.lean", "line": 16, "col": 3 }
```

Result shape:

```json
{ "id": ["node-0"] }
```

Notes:

- the result contains an array because a source position may expose multiple goal contexts
- the returned ids are opaque and transient

### `get_hover`

Return hover text at a source position.

Request params:

```json
{ "path": "/path/to/File.lean", "line": 10, "col": 26 }
```

Result shape when present:

```json
{
  "text": "...",
  "range": {
    "start": { "line": 10, "col": 26 },
    "stop": { "line": 10, "col": 34 }
  }
}
```

Notes:

- result type is `Option HoverResult`
- `null`/missing result means no hover content was found
- on `informal[...]` sites, rich preview text may replace ordinary Lean hover

### `get_plain_goal`

Return pretty-printed tactic goals at a source position.

Request params:

```json
{ "path": "/path/to/File.lean", "line": 16, "col": 3 }
```

Result shape:

```json
{
  "goals": ["n : Nat\n⊢ n + 0 = n"],
  "rendered": "n : Nat\n⊢ n + 0 = n"
}
```

Notes:

- result type is optional
- multiple goals are joined into `rendered` with separator text in the worker

### `get_plain_term_goal`

Return the expected type/term-goal at a source position.

Request params:

```json
{ "path": "/path/to/File.lean", "line": 13, "col": 3 }
```

Result shape:

```json
{
  "goal": "⊢ Nat",
  "range": {
    "start": { "line": 13, "col": 3 },
    "stop": { "line": 13, "col": 4 }
  }
}
```

### `get_infoview`

Return a bundled info-view-style result.

Request params:

```json
{ "path": "/path/to/File.lean", "line": 12, "col": 38 }
```

Result shape:

```json
{
  "hover": { ... },
  "plainGoal": { ... },
  "plainTermGoal": { ... }
}
```

Any of those fields may be absent.

### `get_goals`

Inspect a previously loaded tactic-state node.

Request params:

```json
{ "path": "/path/to/File.lean", "id": "node-0" }
```

Result shape:

```json
{
  "goals": ["n : Nat\n⊢ n + 0 = n"]
}
```

### `run_tactic`

Run one tactic from a previously loaded tactic-state node.

Request params:

```json
{ "path": "/path/to/File.lean", "id": "node-0", "tactic": "simpa" }
```

Result shape:

```json
{
  "goals": [],
  "nextId": "node-1"
}
```

Semantics:

- the original node remains unchanged
- a fresh node id is allocated for the next state
- if the tactic solves the goal, `goals` may be empty

### `run_tactic_steps`

Run a sequence of tactics from an initial node.

Request params:

```json
{
  "path": "/path/to/File.lean",
  "id": "node-2",
  "tactics": ["intro h", "exact And.intro h.right h.left"]
}
```

Result shape:

```json
{
  "results": [
    { "goals": ["..."], "nextId": "node-3" },
    { "goals": [], "nextId": "node-4" }
  ]
}
```

Notes:

- the hub implements this as repeated `run_tactic` calls under the session lock
- `tactics` must be non-empty

### `shutdown`

Stop all active sessions and terminate cleanly.

Request params:

```json
{}
```

Result shape:

```json
{ "stopped": 1 }
```

`stopped` is the number of worker sessions that were shut down.

## Knowledge-base method family

The server also exposes direct knowledge-base operations.
All of these methods take object-shaped params and accept an optional `root` path.
If `root` is omitted, the server uses the default knowledge-base root policy relative to its cwd.

Implemented methods:

- `knowledgebase_init`
- `knowledgebase_status`
- `knowledgebase_list`
- `knowledgebase_show`
- `knowledgebase_get_body`
- `knowledgebase_get_metadata`
- `knowledgebase_get_paths`
- `knowledgebase_create`
- `knowledgebase_rename`
- `knowledgebase_delete`
- `knowledgebase_set_body`
- `knowledgebase_replace_metadata`
- `knowledgebase_validate_metadata`
- `knowledgebase_validate_storage`
- `knowledgebase_validate_node`
- `knowledgebase_validate_all`
- `knowledgebase_search_text`
- `knowledgebase_search_tag`
- `knowledgebase_relationships_outgoing`
- `knowledgebase_relationships_incoming`
- `knowledgebase_relationships_related`

Representative request shapes:

```json
{ "root": "/path/to/knowledgebase" }
{ "root": "/path/to/knowledgebase", "id": "group.basic.definition" }
{ "root": "/path/to/knowledgebase", "query": "inverse", "limit": 10 }
```

Representative result shapes:

```json
{ "root": "/path/to/knowledgebase", "initialized": true, "nodeCount": 1, "manifest": { ... } }
{ "nodes": [{ "id": "group.basic.definition", "title": "Definition of group", ... }] }
{ "id": "group.basic.definition", "body": "..." }
{ "oldId": "analysis.uniform_continuity", "stored": { "node": { ... }, "paths": { ... } } }
```

`knowledgebase_replace_metadata` expects structured metadata JSON under the `metadata` field, not CLI-rendered JSON text.

## Informal method family

The server also exposes direct informal-layer queries.
Environment-backed methods require a non-empty `modules` array of Lean module names as strings.
`informal_present` is knowledge-base-backed and takes an optional `root` instead.

Implemented methods:

- `informal_status`
- `informal_decls`
- `informal_decl`
- `informal_refs`
- `informal_ref`
- `informal_decl_deps`
- `informal_ref_deps`
- `informal_present`

Representative request shapes:

```json
{ "modules": ["AFTKTest.Informal.Fixtures.Basic"] }
{ "modules": ["AFTKTest.Informal.Fixtures.Basic"], "declName": "AFTKTest.Informal.Fixtures.Basic.multiRef" }
{ "root": "/path/to/knowledgebase", "ref": "group.basic.definition", "mode": "rich", "bodyMode": "preview" }
```

Representative result shapes:

```json
{ "trackedDeclarations": 8, "trackedReferences": 5, "declarationsWithMultipleReferences": 2 }
{ "entries": [{ "declName": "AFTKTest.Informal.Fixtures.Basic.multiRef", "refs": ["group.basic.definition"], "refCount": 1 }] }
{ "mode": "rich", "summary": { ... }, "payload": { ... }, "bodyMode": "preview" }
```

Informal declaration names are transported as plain strings rather than Lean `Name` JSON values.

## Shared value types

### Source positions

All public source positions are 1-based:

```json
{ "line": 12, "col": 38 }
```

### Source ranges

```json
{
  "start": { "line": 12, "col": 38 },
  "stop": { "line": 12, "col": 60 }
}
```

## Error model

The protocol uses standard JSON-RPC invalid-params/internal errors where appropriate and also defines AFTK-specific server error codes.

### Standard invalid params

Used for request-shape problems and bad line/column values.
Example cases:

- missing params object
- `line = 0`
- `col = 0`
- malformed tactic text that fails parser validation

### AFTK-specific error codes

| Code | Meaning |
| --- | --- |
| `-32001` | tactic failed |
| `-32010` | file not open |
| `-32011` | file changed; reopen required |
| `-32012` | worker unavailable |
| `-32013` | stale or unknown node id |
| `-32020` | domain not found |
| `-32021` | domain validation error |
| `-32022` | domain conflict |
| `-32023` | generic domain error |

#### `-32001` tactic failed

The tactic parsed and was executed, but Lean reported failure.
The error data carries the rendered failure message.

#### `-32010` file not open

A file-scoped query was issued before `open`.

#### `-32011` file changed; reopen required

The hub detected that the file stamp changed since the session was opened.
The old session is invalidated and must be reopened.

#### `-32012` worker unavailable

The worker process died or became unavailable.
The hub removes the session and reports the failure.

#### `-32013` stale or unknown node id

A tactic-state node id is unknown in the current worker session, or it became stale after reopen/restart.

#### `-32020` / `-32021` / `-32022` / `-32023` domain errors

These are used for direct knowledge-base and informal-layer operations.
The JSON-RPC error `data` is structured and preserves lower-layer identity:

```json
{
  "layer": "knowledgebase",
  "code": "node.notFound",
  "message": "Node not found: group.basic.missing",
  "exitCode": 3
}
```

Semantics:

- `-32020` = not found
- `-32021` = validation error
- `-32022` = conflict
- `-32023` = other domain-level failure

## Public behavior worth relying on

The following protocol behaviors are directly exercised by the current test suite:

- second `open` on an unchanged file reuses the worker and returns `opened = false`
- `close` is idempotent
- line/column positions are 1-based
- changed files invalidate sessions with `-32011`
- dead workers surface `-32012`
- stale node ids surface `-32013`
- informal hover can return rich knowledge-base-backed text

## Minimal example session

A short real session looks like this:

```json
{"jsonrpc":"2.0","id":0,"method":"open","params":{"path":"/path/to/Semantics.lean"}}
{"jsonrpc":"2.0","id":1,"method":"get_hover","params":{"path":"/path/to/Semantics.lean","line":10,"col":26}}
{"jsonrpc":"2.0","id":2,"method":"load_node","params":{"path":"/path/to/Semantics.lean","line":16,"col":3}}
{"jsonrpc":"2.0","id":3,"method":"run_tactic","params":{"path":"/path/to/Semantics.lean","id":"node-0","tactic":"simpa"}}
{"jsonrpc":"2.0","id":4,"method":"shutdown","params":{}}
```

## Internal boundary

There is also a hub↔worker JSON-RPC boundary with worker-local methods such as worker `get_hover`, worker `load_node`, and worker `run_tactic`.
That boundary is implemented in code, but most external consumers only need the public hub surface documented above.
