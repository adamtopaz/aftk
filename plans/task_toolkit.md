# Plan: task toolkit for agent use

## Goal

Add a small Pydantic AI toolkit that lets agents **inspect task state and record structured progress** while keeping the Python task manager in control of lifecycle transitions and scheduling.

The key architectural constraint from `plans/tasks.md` still applies:

> Python orchestration owns the task graph and task lifecycle. The model should get a narrow, safe task-facing surface rather than broad control over the scheduler.

So this toolkit should primarily help an agent:

- inspect the current task and nearby task context
- inspect run/task summaries when helpful
- attach notes, artifacts, and task proposals
- optionally perform a few tightly-scoped advanced task operations later

It should **not** make the model the owner of `claim -> complete/fail/cancel` transitions in v1.

---

## What I inspected

### Existing task library

I read the current task implementation in:

- `aftk/tasks/models.py`
- `aftk/tasks/graph.py`
- `aftk/tasks/store.py`
- `aftk/tasks/manager.py`
- `aftk/tasks/planner.py`
- `aftk/tasks/prompts.py`
- `aftk/tasks/__init__.py`
- `plans/tasks.md`

### Existing toolkit patterns in this repo

I read the current toolkit implementations and tests in:

- `aftk/toolkits/coding/_toolkit.py`
- `aftk/toolkits/coding/errors.py`
- `aftk/toolkits/coding/models.py`
- `aftk/toolkits/coding/__init__.py`
- `aftk/toolkits/aftk/_toolkit.py`
- `aftk/toolkits/aftk/errors.py`
- `aftk/toolkits/aftk/models.py`
- `aftk/toolkits/aftk/__init__.py`
- `tests/python/test_coding_toolkit.py`
- `tests/python/test_pydantic_ai_toolkit.py`
- `aftk/app.py`

### Pydantic AI docs

I read `https://ai.pydantic.dev/llms.txt` and then followed the relevant linked docs/pages for toolset design:

- `toolsets/index.md`
- `tools/index.md`
- `tools-advanced/index.md`
- `api/toolsets/index.md`
- `api/tools/index.md`
- `retries/index.md`

The most relevant points from those docs for this plan are:

1. `FunctionToolset`, `CombinedToolset`, and `WrapperToolset` are the right building blocks.
2. Tool calls may run concurrently unless marked `sequential=True`.
3. Tool definitions support metadata and per-step preparation/filtering.
4. Validation failures and `ModelRetry` turn into retry prompts automatically.
5. Approval wrappers exist, but they should be optional and layered on top.

---

## State of the task library today

The task library is already in good shape for a toolkit wrapper.

### Already implemented

The current `aftk.tasks` package already provides:

- Pydantic task/run/attempt/artifact models
- graph validation and cycle detection
- derived scheduler status (`ready`, `blocked`, etc.)
- in-memory and file-backed stores
- `TaskManager` as the central mutation/transition API
- orchestration helpers:
  - `execute_next_ready_task`
  - `execute_ready_tasks_until_blocked`
- prompt rendering helpers
- planner helpers from informal dependency results

### Important current boundaries

The current manager API already centralizes the stateful operations we want the toolkit to wrap:

- `get_task`
- `list_tasks`
- `ready_tasks`
- `blocked_tasks`
- `terminal_tasks`
- `dependency_tasks`
- `scheduler_status`
- `add_task` / `add_tasks`
- `add_dependency`
- `requeue_task`
- `cancel_task`
- `attach_artifact`
- `attach_note`

And the orchestrator currently owns the lifecycle transitions:

- `claim_task`
- `complete_task`
- `fail_task`
- `cancel_task` as a run-control action

That is a good split. The toolkit should sit on top of this, not bypass it.

### What is missing today

There is currently no agent-facing task toolkit:

- no `aftk.toolkits.tasks` package
- no task-tool input/output models
- no structured task-tool error envelope
- no tests for agent-driven task inspection/progress recording
- no helper for composing a task-aware agent with `CodingToolkit` + `AftkToolkit`

---

## Design principles

1. **Wrap the task manager; do not duplicate task logic.**
   The toolkit should be a thin adapter over `TaskManager`.

2. **Default to safe, task-scoped agent operations.**
   Executor agents should inspect state and append notes/artifacts, not rewrite the scheduler.

3. **Keep orchestration in Python, not in tool calls.**
   The orchestrator still decides when tasks are claimed, completed, failed, retried, or expanded.

4. **Follow the repo’s existing toolkit pattern.**
   Use the same broad structure as `CodingToolkit` and `AftkToolkit`:
   - wrapper toolset
   - structured success/failure envelopes
   - separate `models.py` and `errors.py`
   - metadata on tool definitions
   - `visit_and_replace` support

5. **Make all task tools sequential.**
   Pydantic AI can run tool calls concurrently by default. The task manager/store are stateful and should remain single-writer in v1.

6. **Return structured failures for domain/state errors.**
   Existing toolkits in this repo expose agent-facing failure envelopes rather than letting domain errors explode into opaque exceptions.

7. **Prefer explicit, prefixed tool names.**
   Use `task_...` names to avoid collisions and make tool intent clear to the model.

---

## Recommendation summary

Implement a new toolkit package:

```text
aftk/toolkits/
  tasks.py
  tasks/
    __init__.py
    _toolkit.py
    errors.py
    models.py
```

with a main class:

- `TaskToolkit`

and agent-facing result envelopes:

- `TaskToolSuccess`
- `TaskToolFailure`
- `TaskToolErrorInfo`

### Default v1 stance

The default toolkit mode should be an **executor-safe surface**:

- read task/run state
- attach notes/artifacts
- record structured proposed subtasks as artifacts
- do **not** expose `claim_task`, `complete_task`, or `fail_task`
- do **not** expose broad graph mutation by default

### Optional later stance

Add a separate **planner/advanced mode** later for controlled graph edits such as:

- add task(s)
- add dependency
- requeue failed task
- cancel pending task
- validate graph

If we expose these later, they should be clearly marked advanced and be easy to wrap with approval requirements.

---

## Proposed package shape

### Files

```text
aftk/toolkits/tasks.py                  # repository layout marker

aftk/toolkits/tasks/__init__.py         # public exports

aftk/toolkits/tasks/models.py          # tool input models + success/failure envelopes + lightweight views

aftk/toolkits/tasks/errors.py          # TaskToolkitExecutionError + exception-to-envelope mapping

aftk/toolkits/tasks/_toolkit.py        # TaskToolkit implementation

tests/python/test_task_toolkit.py      # schema/behavior tests
```

### Public exports

`aftk/toolkits/tasks/__init__.py` should export:

- `TaskToolkit`
- `TaskToolErrorInfo`
- `TaskToolFailure`
- `TaskToolResult`
- `TaskToolSuccess`

This should mirror the export style of the existing coding and AFTK toolkits.

---

## Toolkit construction and scoping

## Recommended constructor

A good v1 shape is:

```python
TaskToolkit(
    manager: TaskManager,
    *,
    current_task_id: str | None = None,
    mode: Literal["executor", "planner"] = "executor",
    read_only: bool = False,
    advanced: bool = False,
    id: str | None = None,
)
```

### Why this shape

- `manager` keeps all state logic centralized in `TaskManager`
- `current_task_id` lets the toolkit be task-scoped for executor runs
- `mode` distinguishes safe executor use from future planner use
- `read_only` mirrors the other toolkits
- `advanced` mirrors `AftkToolkit`
- `id` matches existing toolkits and keeps the door open for durable execution compatibility later

### Recommended v1 behavior by mode

#### `mode="executor"`

- expects `current_task_id` for the most useful experience
- read tools can inspect the whole run
- write tools are scoped to the current task by default
- cross-task mutation should be rejected
- no lifecycle-finalization tools
- no graph-edit tools by default

#### `mode="planner"`

- does not require `current_task_id`
- can expose broader read tools
- advanced graph-edit tools may be enabled when `advanced=True`
- still should not own raw scheduler claiming/completion in v1

---

## Recommended v1 tool surface

## Basic executor-safe tools

These are the tools I recommend for the first implementation.

| Tool | Mutates | Purpose |
|---|---:|---|
| `task_current` | no | Return the current bound task with scheduler status and dependency summaries. |
| `task_get` | no | Return one task by id with scheduler status and dependency summaries. |
| `task_run_summary` | no | Return run-level counts and task summaries. |
| `task_list_ready` | no | Return ready-task summaries. |
| `task_list_blocked` | no | Return blocked-task summaries. |
| `task_add_note` | yes | Attach a note artifact to the current task by default. |
| `task_add_artifact` | yes | Attach a structured artifact to the current task by default. |
| `task_propose_tasks` | yes | Validate and record proposed follow-up tasks as an artifact, without mutating the graph. |

### Why this surface is a good v1

It gives agents the most useful task abilities without giving them scheduler authority:

- inspect current work
- inspect nearby run state
- leave structured breadcrumbs
- suggest follow-up work safely

That fits the design decision in `plans/tasks.md` that orchestration, not the model, should remain in control.

---

## Tools to exclude from default v1

These should **not** be exposed in the default executor toolkit:

- `task_claim`
- `task_complete`
- `task_fail`
- `task_execute_next`
- direct raw store access
- full run-state replacement
- arbitrary task deletion
- arbitrary dependency rewrites

### Why exclude them

These tools would let the model take over scheduling and lifecycle authority. That would work against the architecture we just implemented.

---

## Optional advanced/planner tools

These can be added later behind `mode="planner"` and `advanced=True`.

| Tool | Mutates | Notes |
|---|---:|---|
| `task_add` | yes | Add one task from a validated task-spec payload. |
| `task_add_tasks` | yes | Add a batch of tasks. |
| `task_add_dependency` | yes | Add one dependency edge. |
| `task_requeue` | yes | Requeue a failed task. |
| `task_cancel` | yes | Cancel a pending/running task when appropriate. |
| `task_validate_graph` | no | Re-run graph validation explicitly. |

### Safety recommendation

If/when we add these tools, they should be easy to wrap with Pydantic AI’s approval wrappers rather than baking approval logic into the toolkit itself.

---

## Agent-facing models

## Result envelopes

Follow the exact high-level pattern used by the current toolkits.

### Success/failure models

Define in `aftk/toolkits/tasks/models.py`:

- `TaskToolErrorInfo`
- `TaskToolSuccess`
- `TaskToolFailure`
- `TaskToolResult`

Suggested common fields:

- `ok: Literal[True/False]`
- `tool: str`
- `data: Any` on success
- `error.kind`
- `error.message`
- `error.retryable`
- `error.suggested_action`
- `error.details`

This keeps the task toolkit behavior consistent with:

- `CodingToolkit`
- `AftkToolkit`

## Input models

The toolkit should define explicit input models for each tool rather than exposing raw `dict[str, Any]` parameters.

Recommended v1 inputs:

- `TaskIdInput`
- `TaskListInput`
- `TaskTargetInput` with optional `task_id`
- `TaskNoteInput`
- `TaskArtifactInput`
- `TaskProposalInput`

### Proposal input

For `task_propose_tasks`, use a validated `TaskSpec`-compatible nested payload. The toolkit should validate the proposals structurally, then store them as an artifact rather than mutating the graph.

That gives us:

- machine-checkable proposals
- no unsafe immediate graph mutation
- a clean upgrade path later if an orchestrator wants to apply approved proposals

## Lightweight output views

The toolkit should probably not return raw `TaskRunState` for everything.

Instead, define small agent-facing views such as:

- `TaskSummaryView`
- `TaskDetailView`
- `TaskRunSummaryView`

These can include:

- task id
- kind
- title
- lifecycle status
- derived scheduler status
- priority
- dependency ids / dependency summaries
- result summary / last error
- attempt count

This keeps responses useful and stable without dumping the entire store for every call.

---

## Error-handling strategy

This is a key part of the implementation.

## Recommendation

Follow the existing toolkit pattern:

1. toolkit/domain exceptions become **structured failure envelopes**
2. tool-call schema validation remains handled by Pydantic AI automatically
3. unknown exceptions still become a generic internal tool failure envelope

### Why this is the right fit here

Pydantic AI’s automatic validation retry flow is useful for malformed arguments, but most task-tool failures are **state/domain facts** rather than “please try the same tool call again differently in the next token”.

Examples:

- task does not exist
- task is blocked
- graph edit would create a cycle
- executor mode tried to mutate a different task
- task cannot be requeued from its current status

Those should come back to the agent as a normal, inspectable failure object, just like the current coding and AFTK toolkits do.

## Exception mapping

Create `TaskToolkitExecutionError` and a `failure_from_exception()` helper in `aftk/toolkits/tasks/errors.py`.

Suggested mappings:

- `TaskNotFoundError` -> `task_not_found`
- `TaskTransitionError` -> `invalid_transition`
- `TaskConflictError` -> `task_conflict`
- `MissingDependencyError` -> `missing_dependency`
- `TaskCycleError` -> `cycle_detected`
- `TaskMappingError` / `TaskGraphError` -> `graph_error`
- executor-scope violations -> `cross_task_write_forbidden` or `no_current_task`
- pydantic/domain validation inside toolkit payload conversion -> `invalid_payload`
- fallback -> `task_tool_internal_error`

### Suggested details payloads

Include structured details where possible, e.g.:

- `task_id`
- `current_task_id`
- `status`
- `scheduler_status`
- `dependency_id`
- `mode`
- `advanced`

This is very useful for agents and for tests.

## `ModelRetry` guidance

Do **not** make `ModelRetry` the primary task error path in v1.

Use it sparingly, if at all.

Recommended default:

- let framework-generated schema validation retries handle malformed arguments
- return structured `TaskToolFailure` for task-state and graph-state problems

That is the most consistent fit with the existing repo toolkits.

---

## Pydantic AI design notes for this toolkit

## Toolset implementation pattern

Implement `TaskToolkit` as a `WrapperToolset[Any]` that wraps one or more `FunctionToolset[Any]`, mirroring the existing toolkits.

Suggested internal structure:

- `_build_read_toolset()`
- `_build_write_toolset()`
- `_build_planner_toolset()`
- `_register(...)`
- `_normalize_result(...)`
- `_resolve_target_task_id(...)`

## Sequential execution

Set `sequential=True` on the function toolsets.

This is important because the Pydantic AI docs say tool calls may otherwise run concurrently. The task manager/store are stateful, and the repository’s task system currently assumes a single writer.

## Tool metadata

Attach metadata similarly to the existing toolkits.

Suggested metadata shape:

```python
{
  "source": "tasks",
  "layer": "task_run",
  "mutates": False,
  "advanced": False,
  "mode": "executor",
}
```

At minimum, carry:

- `source`
- `layer`
- `mutates`
- `advanced`
- `mode`

This makes filtering and testing easy.

## Docstring and schema requirements

Use the same pattern as the existing toolkits:

- `docstring_format="google"`
- `require_parameter_descriptions=True`

## Per-step preparation

We do **not** need heavy use of `prepare` or `PreparedToolset` in v1, but the docs make it clear they are a good option for later dynamic filtering.

Possible later uses:

- hide `task_current` when no current task is bound
- hide planner tools unless orchestration has put the agent in planner mode
- change descriptions dynamically based on the current task kind

For v1, constructor-time filtering is simpler.

## Approval wrappers

If we later expose graph mutations, prefer Pydantic AI’s approval wrappers around the advanced toolset rather than embedding human-approval mechanics directly into the task toolkit.

---

## Integration with the current agent stack

## Default recommendation

Do **not** change `aftk.app.build_agent()` to always include the task toolkit.

Reason:

- most agent runs are not task-manager-backed
- `TaskToolkit` requires a live `TaskManager`
- always attaching it would over-couple the default agent builder to the task system

## Recommended integration pattern

Task-aware orchestration code should compose toolsets explicitly:

```python
[
  CodingToolkit(...),
  AftkToolkit(...),
  TaskToolkit(manager, current_task_id=task.id, mode="executor"),
]
```

### Optional ergonomics later

If this becomes common, add a helper such as:

- `build_task_agent(...)`
- or `build_agent(..., extra_toolsets=[...])`

But that should be a follow-up, not a prerequisite.

---

## Recommended implementation phases

## Phase 1: toolkit models and error mapping

Implement:

- `aftk/toolkits/tasks/models.py`
- `aftk/toolkits/tasks/errors.py`
- public exports and layout markers

Deliverables:

- success/failure envelopes
- input models
- lightweight output views
- exception-to-error mapping helpers

### Phase 1 success criteria

- task-tool models serialize cleanly
- known task exceptions map to stable error kinds
- unknown exceptions map to a generic internal failure

---

## Phase 2: read-only task toolkit

Implement `TaskToolkit` with the read surface:

- `task_current`
- `task_get`
- `task_run_summary`
- `task_list_ready`
- `task_list_blocked`

Deliverables:

- `aftk/toolkits/tasks/_toolkit.py`
- schema/behavior tests

### Phase 2 success criteria

- tools appear with expected metadata and schemas in `TestModel`
- task views are normalized consistently
- missing-task errors return `TaskToolFailure`
- all tools are sequential

---

## Phase 3: scoped write tools for executor agents

Add:

- `task_add_note`
- `task_add_artifact`
- `task_propose_tasks`

Deliverables:

- scoped target resolution (`current_task_id` by default)
- cross-task write rejection in executor mode
- persistence tests using `InMemoryTaskRunStore`

### Phase 3 success criteria

- note/artifact writes persist in manager state
- proposals are validated and stored as artifacts
- executor agents cannot mutate unrelated tasks
- errors are returned as structured failures

---

## Phase 4: optional advanced/planner tools

Add only if needed:

- `task_add`
- `task_add_tasks`
- `task_add_dependency`
- `task_requeue`
- `task_cancel`
- `task_validate_graph`

### Phase 4 success criteria

- advanced tools are hidden unless explicitly enabled
- graph/state errors are still routed through the failure envelope
- advanced surfaces remain clearly separate from executor-safe defaults

---

## Testing plan

Add `tests/python/test_task_toolkit.py` modeled after the existing toolkit tests.

## Tests to include

### 1. Schema/exposure tests

Check that:

- expected tool names are exposed in executor mode
- planner/advanced tools are hidden by default
- metadata is present and correct
- tools are marked sequential
- parameter schema descriptions exist

### 2. Read behavior tests

Check that:

- `task_current` returns the bound task with derived scheduler status
- `task_get` returns dependency summaries
- ready/blocked listings are correct
- missing task ids return `TaskToolFailure`

### 3. Write behavior tests

Check that:

- `task_add_note` persists a note artifact
- `task_add_artifact` persists a structured artifact
- `task_propose_tasks` stores validated proposals as artifacts
- executor mode rejects cross-task writes cleanly

### 4. Error mapping tests

Check that:

- `TaskNotFoundError` -> `task_not_found`
- `TaskTransitionError` -> `invalid_transition`
- cycle/dependency errors -> graph-related kinds
- unknown exception -> `task_tool_internal_error`

### 5. Composition tests

Check that the toolkit can be composed with the others in an agent run:

- `TaskToolkit` + `CodingToolkit`
- `TaskToolkit` + `AftkToolkit`
- or all three together with `TestModel`

This only needs to confirm clean schema exposure and call routing, not a huge end-to-end workflow.

---

## Open questions

1. **Do we want executor agents to see the whole run by default, or only bounded summaries?**
   My recommendation: allow read access to the run, but keep writes task-scoped.

2. **Should task proposals be stored as artifacts or as pending tasks immediately?**
   My recommendation: artifacts first, real graph mutation later.

3. **Do we want a separate `PlannerTaskToolkit` class later?**
   Possibly, but a `mode=` split is enough for v1.

4. **Should task-aware agent creation get a helper in `aftk.app`?**
   Probably later, after the toolkit API stabilizes.

5. **Should advanced planner tools require approval by default?**
   Not necessarily in v1, but they should be easy to wrap with approval.

---

## Recommended first deliverable

The best first vertical slice is:

1. create `TaskToolkit` with read-only tools
2. expose it to a `TestModel` agent
3. verify schemas/metadata/tool names
4. call `task_current` and `task_add_note`
5. verify the manager state changed as expected
6. verify domain failures come back as `TaskToolFailure`

That slice proves the key pieces:

- task state can be safely exposed to agents
- task bookkeeping can be recorded via tools
- errors are handled consistently with the repo’s other toolkits
- orchestration still owns lifecycle transitions

---

## Summary

The task toolkit should be a **thin, sequential, structured wrapper** over `TaskManager`, following the same implementation pattern as the existing coding and AFTK toolkits.

For v1, it should focus on:

- task inspection
- run summaries
- note/artifact attachment
- safe recording of proposed follow-up tasks

and it should **not** hand scheduler control to the model.

That gives agents the task awareness they need while preserving the task architecture we just put in place.
