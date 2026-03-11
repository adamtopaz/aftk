# Plan: async Python client for `aftk_server`

## Goal

Implement a fully async Python client for the public `aftk_server` JSON-RPC hub.
The client should model request/response types with Pydantic, speak the server's newline-delimited stdio JSON-RPC protocol, expose a clean async API for the documented public hub methods, and be able to start the server from the correct **Lake project root** when AFTK is being used as a dependency in another Lean 4 project.

## Research summary

### 1. What the server actually is

From `docs/server/overview.md`, `docs/server/library.md`, `docs/server/protocol.md`, `docs/server/testing.md`, and the Lean implementation under `AFTK/Server/**` and `AFTK/FileWorker/**`:

- `aftk_server` is the **public hub**.
- `aftk_file_worker <path>` is an **internal per-file worker**.
- The hub manages **one worker per open Lean file**.
- External consumers should talk to the **hub only**; the worker boundary is an internal implementation detail.

### 2. Transport and framing

The public protocol is:

- JSON-RPC 2.0
- UTF-8 JSON
- **newline-delimited over stdio**
- one JSON message per line
- `params` are always **object-shaped**

So this is **not** LSP-style `Content-Length` framing and **not** HTTP.
A Python client should use `asyncio` streams/subprocess APIs directly; no web client is needed.

### 3. Public hub methods

The public methods implemented by `aftk_server` are:

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

These are registered in `AFTK/Server/Hub.lean` and documented in `docs/server/protocol.md`.

### 4. Important semantics the client must preserve

#### File/session lifecycle

- `open { path }` opens or reuses a worker session.
- `open` returns a **canonical session path**.
- A second `open` on an unchanged file returns `opened = false`.
- `close` is idempotent.
- File-scoped methods fail with `-32010` if the file is not open.

#### File invalidation

The hub stamps each file by:

- modification time
- byte size

If the file changes on disk after `open`, the hub invalidates the session and returns `-32011` (`file changed; reopen required`).
This matters because the Python client should **surface this error**, not silently retry or auto-reopen.

#### Worker liveness

If a worker dies, the hub removes the session and returns `-32012` (`worker unavailable`).
The client should surface this as a typed exception.

#### Source positions

All public source positions are **1-based**:

- `line >= 1`
- `col >= 1`

The client should validate this client-side with Pydantic, while still treating the server as the source of truth.

#### Tactic-state node ids

`load_node` returns opaque node ids like `node-0`.
These ids are:

- session-local
- file-local
- transient
- invalidated by reopen/restart

If a node id becomes stale, the server returns `-32013`.
The client should not hide this by automatic reopen/reload behavior.

#### Worker snapshot model

The worker is a **one-shot snapshot of the file on disk**. It does not support incremental in-memory document updates.
That means the Python client is a client for the **current file-on-disk protocol**, not an editable-document/LSP client.

### 5. Error model

From `AFTK/Server/Protocol.lean` and `docs/server/protocol.md`:

Standard JSON-RPC errors used here:

- `-32602` invalid params
- `-32603` internal error

AFTK-specific errors:

- `-32001` tactic failed
- `-32010` file not open
- `-32011` file changed; reopen required
- `-32012` worker unavailable
- `-32013` stale or unknown node id

Error `data` is currently a string for the AFTK-specific cases (path, message, or node id), so the Python exception layer should preserve `code`, `message`, and raw `data`.

### 6. Important process-level detail: `shutdown` is not enough by itself

The docs say `shutdown` stops active sessions, and that is true.
But the current Lean implementation of the public `shutdown` handler only stops worker sessions; it does **not** itself terminate the hub event loop in `AFTK/Server/Main.lean`.
The Lean subprocess test harness still kills the hub process in cleanup.

So the Python client should treat shutdown this way:

1. send `shutdown {}` as a normal JSON-RPC request
2. then close stdin / stop the transport
3. wait for process exit
4. terminate/kill if the process does not exit promptly

That should be part of the client's `aclose()` / context-manager cleanup path.

### 7. Lake project root / dependency context matters

This repo is meant to be used as a dependency in other Lean 4 projects, so the Python client cannot assume that the correct working directory is the AFTK repo itself.

This is especially important because the hub starts workers with:

```text
lake exe aftk_file_worker <path>
```

from `AFTK/Server/Hub.lean`, and that child process inherits the hub process environment and working directory.
So the hub must be launched from the **root of the consumer Lake project** where:

- the target Lean file belongs
- the project's `lakefile.lean` / `lakefile.toml` and `lean-toolchain` live
- Lake can resolve AFTK as a dependency
- the hub's worker-spawn path will also run in the same valid Lake context

This means `cwd` is not just a generic subprocess option; it is part of the correctness of the client API.
The client design should therefore make the Lake project root a first-class concept, not an afterthought.

## Design goals for the Python client

1. **Fully async**
   - all public operations are `async def`
   - subprocess startup/shutdown is async
   - multiple requests can be in flight concurrently

2. **Pydantic-modeled wire types**
   - request params and result payloads are Pydantic models
   - JSON-RPC error payloads are modeled too
   - method wrappers validate both outgoing and incoming data

3. **Mirror the public hub surface first**
   - match the documented server methods one-for-one
   - do not expose direct worker methods as public API

4. **Preserve server semantics**
   - do not auto-reopen on `-32011`
   - do not auto-retry on `-32012`
   - do not cache node ids across reopen/restart

5. **Be Lake-project aware**
   - make the consumer project's Lake root a first-class startup/configuration input
   - ensure the hub subprocess runs from the same project root the target Lean file belongs to
   - support AFTK being used as a dependency rather than assuming this repository is the active project

6. **Keep dependencies small**
   - use `asyncio`, `json`, and `asyncio.subprocess` from the stdlib
   - use `pydantic` v2 for validation/modeling
   - avoid pulling in a separate JSON-RPC or networking stack unless a real need appears

## Proposed package structure

Exact package placement can be decided when we touch packaging, but the client itself should be split roughly like this:

```text
<a python package>/
  __init__.py
  client.py          # public async client API
  transport.py       # subprocess + read loop + request/response multiplexing
  models.py          # Pydantic request/result models for AFTK methods
  jsonrpc.py         # JSON-RPC envelope + error models
  errors.py          # typed exception hierarchy
```

If we also want ergonomic file-bound helpers, add:

```text
  session.py         # optional per-open-file convenience wrapper
```

## Pydantic modeling plan

Use **Pydantic v2**.

### Model conventions

- Requests: strict outgoing shape, `extra="forbid"`
- Responses: tolerate additive fields, `extra="ignore"`
- Use Pythonic field names where it improves ergonomics, with aliases for wire compatibility
- Serialize with `model_dump(by_alias=True, exclude_none=True)`
- Parse responses with `TypeAdapter(...)` / `model_validate(...)`

### Core value models

```text
SourcePosition
  line: int  (>= 1)
  col: int   (>= 1)

SourceRange
  start: SourcePosition
  stop: SourcePosition

HoverResult
  text: str
  range: SourceRange | None

PlainGoalResult
  goals: list[str]
  rendered: str

PlainTermGoalResult
  goal: str
  range: SourceRange | None

InfoViewResult
  hover: HoverResult | None
  plain_goal: PlainGoalResult | None        # alias: plainGoal
  plain_term_goal: PlainTermGoalResult | None  # alias: plainTermGoal

LoadNodeResult
  ids: list[str]    # alias: id

GetGoalsResult
  goals: list[str]

RunTacticResult
  goals: list[str]
  next_id: str      # alias: nextId

RunTacticStepsResult
  results: list[RunTacticResult]

OpenResult
  path: str
  opened: bool

CloseResult
  path: str
  closed: bool

ShutdownResult
  stopped: int
```

### Request param models

```text
OpenParams
  path: str

CloseParams
  path: str

FileLocationParams
  path: str
  line: int  (>= 1)
  col: int   (>= 1)

FileNodeParams
  path: str
  node_id: str   # alias: id

RunTacticParams
  path: str
  node_id: str   # alias: id
  tactic: str

RunTacticStepsParams
  path: str
  node_id: str   # alias: id
  tactics: list[str]  (min length 1)

ShutdownParams
  <empty model>
```

### JSON-RPC envelope models

We should also model the JSON-RPC envelope, at least enough to validate protocol-level behavior:

```text
JsonRpcRequest
  jsonrpc: Literal["2.0"] = "2.0"
  id: int
  method: str
  params: dict[str, Any]

JsonRpcErrorObject
  code: int
  message: str
  data: Any | None

JsonRpcSuccessResponse
  jsonrpc: Literal["2.0"]
  id: int
  result: Any

JsonRpcErrorResponse
  jsonrpc: Literal["2.0"]
  id: int | None
  error: JsonRpcErrorObject
```

Implementation note: for successful responses, it is probably simpler to parse the envelope first and then validate `result` against the expected method-specific result type, rather than trying to build a large generic response hierarchy.

## Async transport/runtime plan

### Process ownership

The core client should manage a spawned local subprocess, defaulting to something like:

```python
["lake", "exe", "aftk_server"]
```

with configurable:

- `command`
- `project_root` (preferred API)
- `cwd` for lower-level overrides if we keep it exposed
- environment overrides

That matters because:

- the server is documented as a stdio subprocess
- relative path resolution depends on process working directory
- Lean/Lake dependency resolution depends on process working directory
- the hub later spawns `lake exe aftk_file_worker <path>` children, which must run in the same valid Lake project context

So the public API should prefer an explicit `project_root` concept rather than a bare generic `cwd` knob.
Internally that `project_root` can be passed as the subprocess `cwd`.

### Lake root resolution strategy

The client should support three startup modes, in this order of preference:

1. **Explicit `project_root` provided by the caller**
   - best for editors, tools, and integrations that already know the active Lean workspace root

2. **Infer from a target Lean file path**
   - walk upward from the file location looking for a Lake project root
   - likely markers: `lakefile.lean` or `lakefile.toml`
   - `lean-toolchain` is a useful corroborating marker but should not be the sole criterion

3. **Fallback to current process working directory**
   - acceptable for scripts already launched from the correct project root
   - should be documented as less reliable

If auto-detection is ambiguous or fails, the client should raise a clear configuration error rather than spawning the server in an arbitrary directory.

### Internal transport responsibilities

`transport.py` should own:

- spawning the subprocess with `asyncio.create_subprocess_exec`
- one background task that reads `stdout` **line by line**
- optional background draining/logging of `stderr`
- one write lock around `stdin.write(...)`
- a monotonically increasing integer request id counter
- a `pending: dict[int, Future]` map for in-flight requests

### Request flow

1. build a params model
2. convert it to a wire dict with aliases
3. wrap it in a JSON-RPC request envelope
4. serialize to one compact JSON line + trailing `\n`
5. write under a single writer lock
6. await the matching future that the stdout reader resolves
7. validate the `result` payload into the expected Pydantic model

### Response reader behavior

The stdout reader task should:

- call `await stdout.readline()` in a loop
- treat EOF as transport closure
- parse each line as JSON
- validate the response envelope enough to extract `id`
- resolve or fail the matching pending future
- treat unknown ids / malformed envelopes as protocol errors

### Cancellation and timeouts

Because the server does not advertise request cancellation semantics, the Python client should treat coroutine cancellation as **local only**.
Recommended approach:

- keep the protocol state consistent even if the caller cancels an `await`
- do not let task cancellation destroy the shared pending-response bookkeeping
- support optional request timeouts at the client layer

A practical implementation is to keep an internal future per request and `await asyncio.shield(future)` from the public method.

### Cleanup / `aclose()`

`aclose()` should:

1. best-effort send `shutdown {}` if the process is still alive
2. close stdin
3. wait for the reader task to finish
4. wait for process exit with a timeout
5. terminate, then kill if needed
6. fail any still-pending requests with a transport-closed exception

The public client should also be an async context manager.

## Public API plan

### Core client

Expose a single public async client, e.g. `AsyncAftkClient`.

Desired usage:

```python
async with AsyncAftkClient(command=["lake", "exe", "aftk_server"], project_root=workspace_root) as client:
    opened = await client.open(file_path)
    hover = await client.get_hover(opened.path, 10, 26)
```

The constructor should make it obvious that `project_root` is the important configuration for dependency-style usage in downstream Lean projects.
If we keep `cwd` at all, it should be framed as a lower-level escape hatch rather than the main entrypoint.

### Public methods

The public API should mirror the documented server methods directly:

```text
start() / aclose()
request(...)
open(path) -> OpenResult
close(path) -> CloseResult
load_node(path, line, col) -> LoadNodeResult
get_hover(path, line, col) -> HoverResult | None
get_plain_goal(path, line, col) -> PlainGoalResult | None
get_plain_term_goal(path, line, col) -> PlainTermGoalResult | None
get_infoview(path, line, col) -> InfoViewResult
get_goals(path, node_id) -> GetGoalsResult
run_tactic(path, node_id, tactic) -> RunTacticResult
run_tactic_steps(path, node_id, tactics) -> RunTacticStepsResult
shutdown() -> ShutdownResult
```

Implementation details:

- public methods should accept `str | pathlib.Path` where natural, but send strings on the wire
- returning typed models is preferable to raw dicts everywhere
- keep one low-level generic `request(method, params_model, result_type)` helper under the hood
- startup should accept either an explicit `project_root` or a target file from which the Lake root can be inferred
- consider a helper such as `AsyncAftkClient.for_file(path)` or `detect_project_root(path)` so callers can easily bind the client to the correct downstream Lake workspace

### Optional ergonomic layer after core API lands

After the one-to-one API is stable, add an optional file-bound helper like `OpenedFileSession`:

```python
session = await client.open_session(path)
hover = await session.get_hover(10, 26)
```

This wrapper should:

- store the canonical path returned by `open`
- reduce repeated path arguments
- remain a thin convenience layer over the exact server semantics

This is useful, but it should be phase 2, not phase 1.

## Exception hierarchy plan

Define a small typed exception layer in `errors.py`.

```text
AftkClientError
  TransportClosedError
  ProtocolError
  ResponseDecodeError
  JsonRpcRequestError
    InvalidParamsError        (-32602)
    InternalJsonRpcError      (-32603)
    TacticFailedError         (-32001)
    FileNotOpenError          (-32010)
    FileChangedError          (-32011)
    WorkerUnavailableError    (-32012)
    StaleNodeError            (-32013)
```

Each raised request error should preserve at least:

- `code`
- `message`
- `data`
- request `method`
- request `id`

That will make debugging much easier.

## Testing plan

The Python tests should mirror the Lean process tests as closely as practical.

### 1. Model tests

- request model validation for 1-based line/col
- `RunTacticStepsParams` rejects empty tactics
- alias behavior (`next_id` <-> `nextId`, `ids` <-> `id`, etc.)
- optional result parsing (`HoverResult | None`)

### 2. Transport tests

- pending request id correlation
- EOF fails all in-flight requests
- malformed response line becomes a protocol error
- concurrent requests do not corrupt the pending map

### 3. Real subprocess integration tests against `aftk_server`

Use the existing fixture files under `tests/server/fixtures/lean/`.
Test at least:

- open / reuse / close / shutdown lifecycle
- `get_hover`
- `get_plain_term_goal`
- `get_plain_goal`
- `load_node` -> `get_goals` -> `run_tactic`
- `run_tactic_steps`
- invalid position params -> `InvalidParamsError`
- file change invalidation -> `FileChangedError`
- stale node after reopen -> `StaleNodeError`
- worker death -> `WorkerUnavailableError`
- rich hover on `informal[...]` fixture
- startup with an explicit `project_root`
- Lake-root auto-detection from a target file path

We should also add at least one test that exercises the intended downstream usage mode: start the client from the root of a separate Lake project that depends on AFTK, then verify that `lake exe aftk_server` and its spawned `aftk_file_worker` children run correctly in that dependency context.

### 4. Async/concurrency tests

Add at least one test that issues several independent queries concurrently to make sure the client is truly async and the request-id multiplexing is correct.

## Suggested implementation phases

### Phase 1: dependencies and skeleton

- add `pydantic` to Python dependencies
- create the client package/module layout
- add base model configuration and JSON-RPC envelope models
- decide the public startup configuration shape for `project_root` / Lake-root detection

### Phase 2: wire models + exceptions

- implement all request/result models for the public hub surface
- implement the typed exception hierarchy
- add unit tests for aliases and validation rules

### Phase 3: async transport

- spawn `aftk_server` asynchronously
- ensure the subprocess starts in the resolved consumer `project_root`
- implement writer lock, id allocation, reader task, and pending-request bookkeeping
- implement graceful cleanup logic
- add transport-level tests

### Phase 4: high-level client API

- implement one-to-one async methods for all public hub methods
- make the client an async context manager
- add the generic `request()` helper
- implement explicit `project_root` configuration and/or file-based Lake-root inference helpers

### Phase 5: integration tests

- add real subprocess tests against fixture Lean files
- cover the documented error codes and lifecycle behavior

### Phase 6: ergonomics and docs

- add a short README/example snippet for the Python client
- optionally add a thin file-bound session wrapper
- decide whether to expose a lower-level attach/connect API later

## Recommended scope for v1

Include in v1:

- async subprocess-managed client
- Pydantic request/result/error models
- typed exceptions
- one-to-one coverage of the documented hub methods
- explicit consumer-`project_root` support, with optional Lake-root inference helpers
- real subprocess integration tests

Do **not** include in v1:

- direct worker clients
- incremental document/update support
- automatic reopen/retry on file changes
- hidden recovery for stale node ids
- speculative caching beyond simple request/result handling

## Acceptance criteria

The client is ready when all of the following are true:

- every documented public hub method has a typed async wrapper
- request/response payloads are modeled with Pydantic
- JSON-RPC errors are mapped to typed Python exceptions
- multiple concurrent requests work correctly
- the client can reliably start `aftk_server` from the correct downstream Lake `project_root`
- cleanup handles the real process behavior of `aftk_server`
- integration tests cover the same main flows already covered by the Lean process tests
