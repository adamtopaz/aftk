# Plan: autoformalize tool-recovery and toolkit session fixes

## Goal

Fix the AFTK framework's agent-tool integration so that:

1. recoverable tool failures stay inside the Pydantic AI agent loop instead of aborting the whole framework run, and
2. agents can explicitly manage Lean file sessions with `open` / `close` before using file-scoped toolkit queries such as `load_node`.

This plan is intentionally focused on the Python framework/tooling layer.
The current Lean server protocol already exposes the needed lifecycle methods.

## Non-goals

- changing the public `aftk_server` JSON-RPC protocol
- silently auto-opening or auto-reopening files inside `aftk_client`
- hiding server lifecycle semantics from non-agent Python users of `aftk_client`

The low-level client should remain protocol-faithful; the agent tool layer should become retry-friendly.

## Research summary

### 1. Latest failure in `../capacity/.aftk/`

The latest failed run is `../capacity/.aftk/runs/run-0005/`.
The new partial-failure logging made the failure path clear:

- `run.json`
  - `agent_role = "initializer"`
  - `status = "failed"`
  - `error_message = "load_node failed with JSON-RPC error -32010: File is not open"`
- `llm-calls.jsonl`
  - first model turn called:
    - `get_project_snapshot_summary`
    - `read_entrypoint`
    - `list_lean_files`
    - `list_source_files`
  - second model turn called:
    - `load_node`
- `tool-calls.jsonl`
  - the failing tool call was:
    - `tool_name = "load_node"`
    - `path = "Capacity.lean"`
    - `line = 1`
    - `col = 1`
- `messages.json`
  - confirms the initializer tried to inspect Lean immediately with `load_node` without opening the file first

So the concrete failing behavior is now known:

- the model asked for `load_node("Capacity.lean", 1, 1)`
- the toolkit surfaced the raw `FileNotOpenError`
- the exception escaped the tool layer and aborted the whole initializer run

### 2. What the server requires

From:

- `docs/server/protocol.md`
- `docs/server/overview.md`
- `AFTK/Server/Hub.lean`
- `AFTK/Server/Protocol.lean`
- `AFTKTest/Server/Process.lean`

Relevant facts:

- the public server surface includes:
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
- file-scoped query methods are implemented through `withFileSession`
- if no file session exists, the server returns `fileNotOpenError`
- `docs/server/protocol.md` explicitly documents `-32010` as:
  - `file not open`
  - “A file-scoped query was issued before `open`.”
- `open` is idempotent in the reuse sense:
  - if the file is already open and unchanged, `opened = false`
  - if the file changed, a new session is spawned
- node ids are session-local and become stale after reopen/restart
- `-32011` means:
  - file changed; reopen required
- `-32013` means:
  - stale or unknown node id

This confirms that the current server semantics are explicit and stateful.
The agent layer should expose those semantics, not pretend they do not exist.

### 3. What the Python client already does

From `aftk_client/client.py` and `tests/python/test_client_integration.py`:

- `AsyncAftkClient` already exposes:
  - `open(path)`
  - `close(path)`
  - all file-scoped query methods
- client integration tests already follow the intended lifecycle:
  - `open`
  - queries / `load_node`
  - `get_goals` / `run_tactic`
  - `close`
- `aftk_client/errors.py` already defines typed exceptions for:
  - `FileNotOpenError`
  - `FileChangedError`
  - `WorkerUnavailableError`
  - `StaleNodeError`

So the low-level client does **not** need a new protocol feature.
The missing surface is at the agent toolkit layer.

### 4. What the agent toolkit currently exposes

From `aftk/agents/tools/toolkit.py` and `aftk/agents/tools/__init__.py`:

- `ToolkitQueryTools` exposes file-scoped Lean tools such as:
  - `load_node`
  - `get_hover`
  - `get_plain_goal`
  - `get_plain_term_goal`
  - `get_infoview`
  - `get_goals`
  - `run_tactic`
  - `run_tactic_steps`
- but it does **not** expose:
  - `open`
  - `close`
- the tool methods mostly call straight through to `AsyncAftkClient`
- if the client raises a typed exception, it currently propagates out of the tool call as a normal Python exception

This mismatch explains the observed failure:

- the model had `load_node`
- it did **not** have `open`
- the resulting client exception was not translated into a model-visible retry prompt

### 5. What Pydantic AI expects for recoverable tool errors

From:

- `https://ai.pydantic.dev/tools-advanced/index.md`
- `https://ai.pydantic.dev/agent/index.md`
- `https://ai.pydantic.dev/api/exceptions/index.md`
- local installed `pydantic_ai` source under `.venv/.../pydantic_ai/`

Relevant framework behavior:

- tool argument validation failures automatically become `RetryPromptPart`
- tool logic can explicitly request recovery by raising `ModelRetry`
- docs state that `ModelRetry` is the correct mechanism when:
  - arguments were syntactically valid
  - but execution found a recoverable problem
  - and the LLM should try again differently
- docs also show `capture_run_messages()` as the debugging path when runs still fail after retries
- `FunctionToolset` defaults to `max_retries = 1` unless overridden

Crucially, the local `pydantic_ai` internals confirm the failure mode we are seeing:

- `_agent_graph.py::_call_tool(...)` converts `ToolRetryError` / `ModelRetry` into a retry prompt
- but ordinary exceptions are **not** converted
- `_agent_graph.py::_call_tools(...)` cancels sibling tasks and re-raises unexpected exceptions

So with the current raw tool wrappers, a `FileNotOpenError` is treated as a hard run failure.
That is exactly the opposite of what we want for recoverable agent-tool mistakes.

### 6. Additional hazard discovered during research: parallel tool execution

From `https://ai.pydantic.dev/tools-advanced/index.md` and local `pydantic_ai/_tool_manager.py`:

- when the model returns multiple tool calls in one response, Pydantic AI executes them concurrently by default
- tools can be marked `sequential=True`
- if any tool in a batch requires sequential execution, Pydantic AI executes the whole batch sequentially

This matters for AFTK because several tool families are stateful and order-sensitive:

- file-session toolkit tools:
  - `open`
  - `close`
  - `load_node`
  - `get_goals`
  - `run_tactic`
  - etc.
- worker coding tools:
  - file writes / replacements / appends
  - `lake_build`
  - general commands

If we expose `open` but still allow concurrent tool execution, a model could emit `open` and `load_node` together and the calls could race.
So proper error handling and proper execution ordering need to be fixed together.

## Design decisions

### 1. Keep `aftk_client` protocol-faithful

Do **not** bake Pydantic-AI-specific retry behavior into `aftk_client`.
The client should continue to:

- mirror the public server methods
- raise typed Python exceptions
- preserve explicit server semantics (`file not open`, `reopen required`, `stale node`, etc.)

The translation to `ModelRetry` belongs in the agent-facing tool wrappers.

### 2. Expose explicit session lifecycle to agents

Add `open` and `close` to the agent toolkit so the model can follow the documented Lean-file session lifecycle.

The tool surface should mirror the server/client names directly:

- `open(path, timeout_seconds=None)`
- `close(path, timeout_seconds=None)`

That keeps the agent surface aligned with:

- `aftk_server`
- `AsyncAftkClient`
- existing server docs/tests

### 3. Translate recoverable tool failures into `ModelRetry`

For agent-exposed tools, recoverable failures should be converted into actionable retry prompts.

Examples:

- `FileNotOpenError`
  - tell the model the file is not open
  - instruct it to call `open(path=...)` first and then retry the query
- `FileChangedError`
  - tell the model the file changed
  - instruct it to call `open(path=...)` again before retrying
- `StaleNodeError`
  - tell the model the node id is stale
  - instruct it to call `load_node(...)` again to obtain a fresh node id
  - mention reopening first if the file changed
- `WorkerUnavailableError`
  - instruct the model to reopen the file session
- LLM-correctable project/coding errors
  - invalid relative path
  - path outside project root
  - reserved path access
  - edit conflict / old text not found
  - missing file / invalid text file
  - invalid argument values

These should become `ModelRetry` with concise, tool-specific guidance.

### 4. Leave truly internal/infrastructure failures as hard failures

Do **not** blanket-convert every exception into `ModelRetry`.
Hard failures should still surface when they indicate:

- a framework bug
- transport corruption
- model/provider failures
- invariant violations
- other conditions the model cannot reasonably repair by choosing a different tool call

### 5. Mark stateful tools as sequential

At minimum, register the following as `sequential=True`:

- toolkit file-session tools:
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
- worker coding tools:
  - `write_file`
  - `replace_in_file`
  - `append_to_file`
  - `run_command`
  - `lake_build`
  - likely also reads/searches for consistency within a single worker step

Read-only project-summary tools can remain non-stateful unless a simpler uniform registration approach is preferable.

### 6. Keep and extend partial-failure telemetry

The latest run diagnosis was only possible because failed-run message/tool traces were captured.
That behavior should remain part of this work, with tests covering failed runs and retry prompts.

## Concrete work plan

### Phase 1: tool error policy layer

Create a small shared utility for agent tool wrappers, likely under `aftk/agents/tools/`, that:

- converts known recoverable exceptions into `ModelRetry`
- preserves the original exception as `__cause__`
- produces short, action-oriented messages suitable for model consumption
- can be reused by:
  - toolkit tools
  - project context tools
  - worker coding tools

Expected mapping surface:

- toolkit/client exceptions from `aftk_client.errors`
- coding exceptions from `aftk.coding.filesystem`
- ordinary `ValueError`, `FileNotFoundError`, `IsADirectoryError`, `NotADirectoryError`
- selected domain errors where the model can try a different argument/value

### Phase 2: expose `open` / `close` in the toolkit

Update `aftk/agents/tools/toolkit.py` so `ToolkitQueryTools` includes:

- `open`
- `close`

Requirements:

- forward to `AsyncAftkClient.open()` / `.close()`
- return the existing `OpenResult` / `CloseResult`
- docstrings must clearly explain:
  - `open` is required before file-scoped Lean queries
  - `open` may reuse an existing session
  - `open` returns the canonical session path
  - `close` is optional but available for explicit cleanup

Also update any framework docs that describe the toolkit/tool permissions.

### Phase 3: re-register tools with explicit retry/ordering metadata

Refactor toolset builders to stop relying only on bare functions.
Use `Tool(...)` or `FunctionToolset.tool(...)` so we can specify:

- `retries=` / toolset `max_retries=`
- `sequential=True` where required
- any custom descriptions/metadata needed for better model behavior

Likely targets:

- `aftk/agents/tools/toolkit.py`
- `aftk/agents/tools/project.py`
- `aftk/agents/tools/coding.py`
- `aftk/agents/tools/__init__.py`

Preferred direction:

- one or more explicit `FunctionToolset(...)` builders with tool registrations that encode retry + sequential policy
- keep the public tool names stable and readable

### Phase 4: add retry-aware wrapper behavior to all model-facing tools

Wrap toolkit/project/coding tool bodies so recoverable failures become `ModelRetry` instead of uncaught exceptions.

Important cases to cover:

#### Toolkit lifecycle / Lean query cases

- `load_node` before `open`
- `get_hover` / goal queries before `open`
- reopen-required after file changes
- stale node ids after reopen
- worker unavailable -> reopen guidance

#### Project context cases

- invalid `limit`
- unknown source-file path
- invalid UTF-8 read
- path outside project root

#### Worker coding cases

- path escapes sandbox
- reserved `.aftk/` access
- missing file / wrong file type
- invalid line ranges
- edit conflict / old text missing / multiple matches
- invalid command args

The retry message should always tell the model what alternative action is available.

### Phase 5: update prompts/tool guidance

Strengthen tool-facing guidance so the models know the intended lifecycle without having to infer it.

Potential changes:

- toolkit docstrings explicitly describe `open` → query → `close`
- initializer/orchestrator/worker instructions mention:
  - file-scoped Lean toolkit tools require `open(path)` first
  - if a tool says a file is not open or changed, use `open(path)` and then retry
  - if a node id is stale, call `load_node(...)` again

This should reduce avoidable retries and improve first-attempt tool use.

### Phase 6: test coverage

Add regression tests across three levels.

#### A. Toolkit/client integration tests

Add/extend tests that verify:

- `open` / `close` are available to agent toolsets
- file-scoped queries succeed after `open`
- `FileNotOpenError` is transformed into a retry prompt instead of aborting the run
- `FileChangedError` produces reopen guidance
- `StaleNodeError` produces refresh guidance

#### B. Agent-loop behavior tests

Add tests with `FunctionModel` or `TestModel` showing:

- model first calls `load_node` on an unopened file
- tool returns a retry prompt
- model then calls `open`
- model eventually retries `load_node`
- run completes instead of crashing

Also add a test where the model returns `open` and `load_node` in one response to verify sequential execution prevents races.

#### C. Framework-runner telemetry tests

Verify that:

- `RetryPromptPart` interactions are logged in `messages.json`
- failed tool attempts appear in `tool-calls.jsonl`
- if a run still fails after retries are exhausted, partial messages/tool traces remain available

### Phase 7: docs

Update the framework docs to describe:

- explicit Lean file-session lifecycle for agent toolkit use
- `open` / `close` availability
- retry-friendly tool behavior
- any changed example expectations for agent/tool traces

Likely doc targets:

- `docs/framework/overview.md`
- `docs/framework/library.md`
- possibly `README.md` if the agent-tool behavior is user-visible enough

## Acceptance criteria

This work is complete when all of the following are true:

1. agents have access to explicit `open` and `close` toolkit tools
2. a model can recover from calling `load_node` before `open` without aborting the whole run
3. recoverable tool mistakes produce model-visible retry prompts (`ModelRetry` / `RetryPromptPart`), not raw uncaught exceptions
4. the low-level `aftk_client` still preserves explicit server semantics and typed exceptions for non-agent callers
5. stateful toolkit/coding tools are registered to execute sequentially
6. the latest `../capacity`-style failure mode is covered by tests
7. failed or retried runs still leave enough trace data under `.aftk/runs/` to explain what happened

## Open questions to resolve during implementation

1. **Retry budget**
   - keep the default of 1 retry for these toolsets, or raise it to 2 for more resilience?
   - recommendation: likely `2` for framework toolsets so one mistaken recovery attempt does not immediately fail the run

2. **How broad should the retry wrapper be?**
   - toolkit only
   - or all model-facing tool families?
   - recommendation: all model-facing tool families should get the same recoverable-error policy

3. **Exact sequential scope**
   - only file-session toolkit tools
   - or the full worker coding toolset too?
   - recommendation: include worker coding tools as sequential because edits/builds are also order-sensitive

4. **Whether to split toolkit registration into stateful vs stateless groups**
   - not required, but it may keep the code clearer:
     - file-session Lean tools
     - stateless knowledge-base / informal tools

## Suggested implementation order

1. land/keep the partial-failure telemetry changes
2. add shared `ModelRetry` conversion utilities
3. expose toolkit `open` / `close`
4. refactor tool registration to support explicit retries + sequential execution
5. add lifecycle/retry tests
6. update docs
