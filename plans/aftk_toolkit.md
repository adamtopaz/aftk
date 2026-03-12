# Plan: Pydantic AI toolkit backed by `AsyncAftkClient`

## Goal

Create a Pydantic AI toolkit that exposes AFTK functionality to agents via the existing
`AsyncAftkClient`, while making tool-call failures **safe for agent runs**:

- raw AFTK/client/server errors should **not** bubble out of tool calls and kill the whole run
- tool-call failures should instead be returned to the model in a **structured, actionable form**
- the toolkit should be a normal reusable Pydantic AI toolset class whose constructor takes a
  client instance

This repository is pre-release, so we should optimize for a clean, agent-friendly design rather
than preserving any earlier framework shape.

---

## Relevant findings from the Pydantic AI docs

After reading `https://ai.pydantic.dev/llms.txt` and following the relevant docs (`toolsets`,
`tools`, `tools-advanced`, `dependencies`, `third-party-tools`, and the `api/toolsets`,
`api/tools`, and `api/exceptions` references), the main design points are:

1. **Toolsets are the right abstraction for reusable bundles of tools.**
   Pydantic AI expects reusable tool collections to be implemented as toolsets.

2. **`FunctionToolset` is the right base for locally implemented Python tools.**
   It gives us schema generation, docstring extraction, argument validation, retries, and tool
   registration.

3. **`WrapperToolset` is the right extension point for changing execution behavior.**
   The docs explicitly recommend subclassing `WrapperToolset` when you want to alter how wrapped
   tools are executed. Our main custom behavior is exactly that: catch client/server failures and
   convert them into agent-visible results instead of letting them crash the run.

4. **Argument validation failures are already handled well by Pydantic AI.**
   If a tool call has malformed arguments, Pydantic AI turns that into a retry prompt for the
   model. That is good behavior, and we should lean on it rather than re-implementing it.

5. **`ModelRetry` is special, but should be used sparingly here.**
   Raising `ModelRetry` does not fail the whole run; it asks the model to try the tool again.
   However, it is still an exception-based control path. For this toolkit, the safer default is
   to return structured error results in-band and reserve exception-based retry behavior for input
   validation or truly exceptional future cases.

6. **Toolsets can attach metadata and be composed/filtered.**
   This is useful because we will likely want several toolkits later, and even this AFTK toolkit
   will likely want read-only vs mutating or basic vs advanced modes.

7. **Tool calls may run concurrently unless marked sequential.**
   Since AFTK has file/session state and mutating knowledge-base operations, concurrency policy
   needs to be chosen deliberately.

---

## High-level design choice

### Chosen shape

Implement the public toolkit as a **`WrapperToolset` around one or more internal
`FunctionToolset`s**.

That gives us:

- normal Pydantic AI tool definition generation from Python callables
- one central place to catch `AftkClientError` and map it to agent-visible results
- easy future composition/filtering by capability

### Why this is better than the alternatives

#### Why not subclass `AbstractToolset` directly?

We do not need fully custom tool discovery or custom parameter schemas from scratch.
The tools are locally implemented Python methods calling an injected client.
`FunctionToolset` already solves the boring but important parts.

#### Why not just subclass `FunctionToolset` directly?

That would work, but the docs make `WrapperToolset` the clearer fit for our main customization:
**changing tool execution behavior**. Wrapping also makes it easier to split the toolkit into
internal sub-toolsets later without changing the public class.

---

## Proposed public API

```python
from aftk import AsyncAftkClient
from aftk.toolkits.aftk import AftkToolkit

client = AsyncAftkClient(project_root=repo_root)
toolkit = AftkToolkit(client)
```

Proposed constructor:

```python
class AftkToolkit(WrapperToolset[object]):
    def __init__(
        self,
        client: AsyncAftkClient,
        *,
        include_lean: bool = True,
        include_knowledgebase: bool = True,
        include_informal: bool = True,
        read_only: bool = False,
        advanced: bool = False,
        close_client_on_exit: bool = False,
        id: str | None = None,
    ) -> None: ...
```

### Notes on these parameters

- `client` is required and is the main dependency injection point.
- `read_only=True` excludes mutating knowledge-base tools.
- `advanced=True` enables low-level tools that expose more of the raw client/server surface.
- `close_client_on_exit=False` keeps ownership simple: by default the injected client is
  caller-owned.
- `id` is optional but useful if we later care about durable execution environments.

---

## Packaging / module layout

This toolkit is specifically for Pydantic AI, so the package should treat `pydantic-ai` as a
normal dependency for toolkit development and use in this repository.

Proposed layout:

```text
aftk/
  toolkits/
    __init__.py
    aftk.py                 # layout marker / public module name
    aftk/
      __init__.py           # public toolkit exports
      _toolkit.py           # AftkToolkit
      models.py             # toolkit input/result models
      errors.py             # toolkit-facing error/result helpers
```

Proposed dependency change:

- add `pydantic-ai` as a normal dependency for this package
- keep the toolkit implementation explicitly Pydantic-AI-specific rather than framework-agnostic

---

## Do not mirror the raw client 1:1

The client surface is good for Python programmers, but not every client method is a good agent
tool. For agent use we should prefer:

- fewer tools
- clearer names
- fewer hidden prerequisites
- fewer unstable/internal identifiers
- more composite operations

### Important example: hide `node_id` when possible

The raw Lean client exposes `load_node`, `get_goals(path, node_id)`, `run_tactic(path, node_id, ...)`,
and `run_tactic_steps(path, node_id, ...)`.

That is fine for Python code, but a poor first experience for an agent because:

- `node_id` is ephemeral
- stale-node errors are easy to trigger
- the agent has to manage an implementation detail

So the toolkit should prefer composite tools like:

- `lean_get_goals_at(path, line, col)`
- `lean_run_tactic_at(path, line, col, tactic)`
- `lean_run_tactic_steps_at(path, line, col, tactics)`

internally performing:

- ensure file is open
- `load_node`
- pick/validate a node id
- call the underlying client method

Low-level state-id tools can be added only in `advanced=True` mode.

### Important example: hide `open`/`close` in normal mode

For agents, file/session management is usually overhead, not value.
Normal query/tactic tools should auto-open the file if needed instead of forcing the model to call
`open` first.

So:

- **default/basic mode:** query/tactic tools auto-open as needed, no explicit `lean_open_file` or
  `lean_close_file` tool
- **advanced mode:** optionally expose explicit open/close/session tools for expert workflows

### Important example: avoid raw metadata replacement in basic mode

`knowledgebase_replace_metadata` is a powerful client method, but it is easy for an LLM to misuse
if it has to provide a full metadata object correctly.

So the toolkit should prefer a higher-level tool like:

- `kb_patch_metadata(...)`

that internally:

- fetches current metadata
- applies a partial patch
- calls `knowledgebase_replace_metadata`

The raw replace call can remain advanced-only.

---

## Proposed tool surface

## 1. Lean tools (basic mode)

These should be state-hiding, position-oriented tools.

### Read/query

- `lean_get_hover(path, line, col)`
- `lean_get_plain_goal(path, line, col)`
- `lean_get_plain_term_goal(path, line, col)`
- `lean_get_infoview(path, line, col)`
- `lean_get_goals_at(path, line, col)`

### Tactic exploration

- `lean_run_tactic_at(path, line, col, tactic)`
- `lean_run_tactic_steps_at(path, line, col, tactics)`

### Internal behavior

Each of these should:

- interpret `path` relative to the injected client's configured project root when appropriate
- auto-open the file before querying
- use `load_node` internally when needed
- if `load_node` yields zero or multiple candidate ids, return a structured error rather than guessing
- return a structured success/error envelope

## 2. Lean tools (advanced mode)

Only when `advanced=True`:

- `lean_open_file(path)`
- `lean_close_file(path)`
- `lean_load_node(path, line, col)`
- `lean_get_goals(path, node_id)`
- `lean_run_tactic(path, node_id, tactic)`
- `lean_run_tactic_steps(path, node_id, tactics)`

These are useful for expert or research-style agents, but not ideal as the default surface.

## 3. Knowledge-base tools (basic mode)

### Read/query

- `kb_status()`
- `kb_list_nodes(prefix=None, kind=None, status=None, tag=None)`
- `kb_show_node(node_id)`
- `kb_get_body(node_id)`
- `kb_search_text(query, limit=None)`
- `kb_search_tag(tag, limit=None)`
- `kb_related(node_id)`
- `kb_validate_node(node_id)`
- `kb_validate_all()`

### Mutating tools (excluded when `read_only=True`)

- `kb_create_node(node_id, title, body=None, kind=None, status=None, summary=None, tags=None, authors=None)`
- `kb_set_body(node_id, body)`
- `kb_patch_metadata(node_id, title=None, kind=None, status=None, summary=None, tags=None, authors=None)`
- `kb_rename_node(old_id, new_id)`
- `kb_delete_node(node_id)`

## 4. Knowledge-base tools (advanced mode)

Only when `advanced=True`:

- `kb_init()`
- `kb_get_metadata(node_id)`
- `kb_get_paths(node_id)`
- `kb_validate_storage()`
- `kb_replace_metadata_raw(node_id, metadata)`
- `kb_relationships_outgoing(node_id)`
- `kb_relationships_incoming(node_id)`

## 5. Informal tools (basic mode)

- `informal_status(modules)`
- `informal_list_decls(modules, prefix=None, ref=None)`
- `informal_get_decl(modules, decl_name)`
- `informal_list_refs(modules, prefix=None)`
- `informal_get_ref(modules, ref)`
- `informal_decl_dependencies(modules, only_leaves=False)`
- `informal_ref_dependencies(modules, only_leaves=False)`
- `informal_present(ref, mode=None, body_mode=None)`

## 6. Tools we should not expose

- `request(...)`
- `start(...)`
- `aclose()`
- `shutdown()`

Those are transport/runtime controls, not agent tools.

---

## Input model design

Tool inputs should **not** blindly reuse the current wire-facing request models.
Those models are appropriate for the client layer, but not always ideal for LLM-facing tools.

### Principles

1. Use **toolkit-specific input models** with agent-friendly field names.
2. Reuse the same validation ideas as the client (positive line/col, non-empty tactic list, etc.).
3. Prefer descriptive names like:
   - `node_id`
   - `decl_name`
   - `only_leaves`
   - `body_mode`
   rather than wire aliases like `id`, `declName`, `onlyLeaves`, `bodyMode`.
4. Omit parameters the injected client already owns/configures unless there is a real agent use case.
   In particular, do not expose `timeout` as a tool parameter.

### Why use dedicated input models?

Pydantic AI builds tool schemas from function signatures and Pydantic models.
Using one Pydantic model per tool gives us:

- better validation
- clearer JSON schema
- explicit field descriptions
- a stable agent-facing API even if the client internals change

---

## Result / error-envelope design

This is the most important part.

## Core rule

**No expected AFTK/client/server exception should escape a tool call.**

Instead, every tool should return a discriminated envelope like:

```python
class AftkToolSuccess(BaseModel):
    ok: Literal[True] = True
    tool: str
    data: Any

class AftkToolErrorInfo(BaseModel):
    kind: str
    message: str
    retryable: bool
    suggested_action: str | None = None
    details: dict[str, Any] | None = None

class AftkToolFailure(BaseModel):
    ok: Literal[False] = False
    tool: str
    error: AftkToolErrorInfo
```

Every public tool returns one of those two shapes.

### Example success

```json
{
  "ok": true,
  "tool": "lean_get_hover",
  "data": {
    "text": "Nat.succ ...",
    "range": {"start": {"line": 10, "col": 24}, "stop": {"line": 10, "col": 32}}
  }
}
```

### Example failure

```json
{
  "ok": false,
  "tool": "lean_run_tactic_at",
  "error": {
    "kind": "tactic_failed",
    "message": "The tactic failed.",
    "retryable": true,
    "suggested_action": "try_different_tactic",
    "details": {
      "jsonrpc_code": -32001
    }
  }
}
```

### Why always wrap success too?

Always wrapping success keeps the shape predictable for the model:

- the model can branch on `ok`
- error handling becomes uniform across all tools
- we do not force the model to infer whether a raw JSON object is data or an error

---

## Error mapping policy

### Layer 1: let Pydantic AI handle malformed tool arguments

If the model passes invalid tool arguments:

- wrong type
- missing field
- invalid enum-like value
- invalid positive integer, etc.

then Pydantic AI should keep doing what it already does: produce a retry prompt.
That is a good fit because the model can often fix the call immediately.

### Layer 2: catch expected AFTK/runtime exceptions and return structured failures

The toolkit should catch at least:

- `AftkClientError`
- all `JsonRpcRequestError` subclasses
- transport/protocol/decode/timeout/configuration errors from the client

and map them into structured `AftkToolFailure` values.

### Layer 3: unexpected implementation bugs

For true programming errors (e.g. `AttributeError`, `KeyError`, our own bug), the safest default is:

- **do not silently swallow them in v1**
- let tests catch them

Possible future option:

- add `catch_unexpected=True` if we later want a “never crash the run” production mode

But the initial design should distinguish expected domain/runtime failures from developer bugs.

---

## Proposed exception-to-error mapping

| Exception type | `kind` | `retryable` | Suggested action |
| --- | --- | --- | --- |
| `InvalidParamsError` | `invalid_params` | `true` | `fix_arguments` |
| `TacticFailedError` | `tactic_failed` | `true` | `try_different_tactic` |
| `FileNotOpenError` | `file_not_open` | `true` | `open_file` |
| `FileChangedError` | `file_changed` | `true` | `reopen_file` |
| `WorkerUnavailableError` | `worker_unavailable` | `true` | `retry` |
| `StaleNodeError` | `stale_node` | `true` | `reload_position` |
| `DomainNotFoundError` | `domain_not_found` | `false` | `check_id_or_create` |
| `DomainValidationError` | `domain_validation` | `true` | `fix_request` |
| `DomainConflictError` | `domain_conflict` | `true` | `choose_different_id` |
| `DomainOperationError` | `domain_operation` | `false` | `inspect_details` |
| `RequestTimeoutError` | `timeout` | `true` | `retry` |
| `TransportClosedError` | `transport_closed` | `true` | `retry` |
| `ProtocolError` | `protocol_error` | `false` | `report_failure` |
| `ResponseDecodeError` | `response_decode_error` | `false` | `report_failure` |
| `ConfigurationError` | `configuration_error` | `false` | `report_failure` |

### Details to preserve in the error payload

For JSON-RPC/domain errors, include as much useful structured context as we reasonably can:

- `jsonrpc_code`
- `method`
- `domain.layer`
- `domain.code`
- `domain.message`
- `domain.exit_code`

For timeout/transport errors include:

- timeout seconds if available
- method name if available

### Important note on `ModelRetry`

For this toolkit, we should **not** convert most AFTK failures into `ModelRetry`.
The point is to let the model reason about the failure, not to hide it behind an automatic retry loop.

The only retry-like behavior we should rely on in v1 is:

- the framework’s built-in tool argument validation retry prompts

---

## Where the error wrapping should live

Centralize it in the public wrapper class.

Pseudo-shape:

```python
class AftkToolkit(WrapperToolset[object]):
    async def call_tool(self, name, tool_args, ctx, tool):
        try:
            result = await super().call_tool(name, tool_args, ctx, tool)
        except AftkClientError as exc:
            return self._failure(name, exc)
        else:
            return self._success(name, result)
```

Benefits:

- one place to enforce policy
- no repetitive try/except in every tool method
- all tools get the same envelope shape

---

## Tool metadata and filtering

Every tool should carry metadata like:

```python
{
  "source": "aftk",
  "layer": "lean" | "knowledgebase" | "informal",
  "mutates": True | False,
  "advanced": True | False,
}
```

This is useful for:

- constructing `read_only=True` variants
- future composition with other toolkits
- diagnostics and testing
- future filtered/prefixed combined toolsets

---

## Concurrency policy

Pydantic AI may execute parallel tool calls by default.
For AFTK, we should be conservative.

## Recommended v1 policy

Mark all AFTK tools as `sequential=True` in v1.

### Why?

Because the toolkit sits on top of:

- a single client/transport
- server-managed open-file state
- tactic exploration state
- mutating knowledge-base operations

A conservative sequential policy gives us:

- simpler reasoning
- fewer race conditions
- easier debugging
- less surprising agent behavior

### Future relaxation

Once usage is proven, we can selectively make clearly read-only tools concurrent, especially:

- `kb_search_text`
- `kb_search_tag`
- `informal_*` read tools

But v1 should prioritize correctness over throughput.

---

## Lifecycle / client ownership

The toolkit constructor receives a client instance, so ownership should be explicit.

## Recommended v1 behavior

- the toolkit **uses** the injected client
- the toolkit does **not** eagerly start it in `__aenter__`
- the toolkit lets the client continue using its own lazy-start behavior
- the toolkit only closes it in `__aexit__` if `close_client_on_exit=True`

### Why not eagerly start?

The client can infer its runtime project root from the first file-oriented call.
Eager startup could lock in the wrong cwd/root behavior too early.
Lazy startup keeps the current client behavior intact.

---

## Documentation / schema quality requirements

Because Pydantic AI uses docstrings and type hints to build tool schemas, the toolkit should have
high-quality tool docs from day one.

## Requirements

- every public tool must have a strong docstring
- every parameter must have a description
- use a consistent docstring style, e.g. Google style
- enable `require_parameter_descriptions=True`

Tool descriptions should include practical guidance when useful, e.g.:

- prerequisites
- what the tool is best for
- what to do when a known error kind is returned

For example, `lean_run_tactic_at` should say that if it returns a `tactic_failed` error, the model
should try a different tactic rather than assume the whole system is broken.

---

## Implementation phases

## Phase 1: package scaffolding

1. Add `pydantic-ai` as a normal dependency for the package.
2. Add `aftk/toolkits/aftk/` toolkit modules and the public `aftk.toolkits.aftk` entrypoint.
3. Add toolkit result/error models.

## Phase 2: internal toolset construction

1. Build internal `FunctionToolset`s for:
   - Lean
   - knowledge-base read
   - knowledge-base write
   - informal
2. Register bound async methods with explicit names/descriptions/metadata.
3. Combine them with `CombinedToolset`.

## Phase 3: wrapper behavior

1. Implement public `AftkToolkit(WrapperToolset)`.
2. Store the client instance.
3. Override `call_tool` to wrap success and catch expected client exceptions.
4. Add optional close-on-exit behavior.

## Phase 4: agent-friendly composites

1. Implement position-based Lean composite tools.
2. Implement `kb_patch_metadata` instead of exposing raw metadata replacement by default.
3. Expose low-level/raw tools only in `advanced=True` mode.

## Phase 5: exports and examples

1. Export the toolkit from the new package.
2. Add a short README example showing:
   - create client
   - create toolkit
   - attach to `Agent(..., toolsets=[toolkit])`

---

## Testing plan

## 1. Unit tests for schema/tool registration

Use Pydantic AI’s `TestModel` to verify:

- tool names
- tool descriptions
- parameter descriptions
- `sequential=True`
- metadata tags
- read-only/advanced filtering

## 2. Unit tests for error policy

Mock or fake the client so each tool path can raise specific exceptions, then verify:

- no `AftkClientError` escapes the tool call
- returned payload has `ok == false`
- `kind`, `retryable`, and `suggested_action` are correct
- domain error details are preserved

## 3. Unit tests for composite behavior

Examples:

- Lean query tools auto-open files before querying
- `lean_get_goals_at` performs load-node internally
- `kb_patch_metadata` fetches then replaces metadata

## 4. Integration tests with the real AFTK server/client

Use the existing fixtures and a real `AsyncAftkClient` to validate representative tools:

- `lean_get_hover`
- `lean_get_goals_at`
- `lean_run_tactic_at`
- `kb_status`
- `kb_search_text`
- `informal_present`

## 5. Failure integration tests

With real fixtures where practical, verify structured failures for cases like:

- tactic failure
- not-found knowledge-base node
- validation/conflict errors
- timeout or transport failure (possibly via a stubbed client)

---

## Open questions / decisions to make during implementation

1. **Name choice:** `AftkToolkit` vs `AftkToolset`.
   - `Toolset` matches Pydantic AI terminology.
   - `Toolkit` matches the broader direction in this repo.
   - My preference is: class name `AftkToolkit`, implemented as a Pydantic AI toolset.

2. **How broad should basic mode be?**
   - My recommendation is a curated, agent-friendly subset first.

3. **Should any client errors become `ModelRetry`?**
   - My recommendation is no for v1, except relying on framework-managed argument validation.

4. **Should unexpected non-AFTK exceptions be swallowed?**
   - My recommendation is no in v1.

5. **Should we later split this into multiple public toolkits?**
   - Very likely yes: Lean, knowledge-base, and informal are natural boundaries.
   - The internal composition proposed above keeps that path open.

---

## Recommendation summary

Implement the first Pydantic AI toolkit as a **client-injected `WrapperToolset` over internal
`FunctionToolset`s**, with the following rules:

- use the injected `AsyncAftkClient`
- expose an **agent-friendly**, not raw-RPC, tool surface
- return a **uniform success/error envelope** for all tool calls
- catch expected AFTK/client/server exceptions centrally in `call_tool`
- let Pydantic AI keep handling malformed tool arguments via retry prompts
- start conservatively with **sequential execution** and a **curated basic-mode surface**
- keep low-level/raw tools behind `advanced=True`

That gives us a clean first toolkit now and a good foundation for the other toolkits we expect to
add later.
