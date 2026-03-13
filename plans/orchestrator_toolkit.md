# Plan: orchestrator toolkit for agent use

## Goal

Add a separate Pydantic AI toolkit for an **orchestrator agent** that has a global view of the task run and is allowed to:

- inspect the full task graph
- plan and mutate task structure
- manage lifecycle transitions and retries
- review and apply worker proposals
- eventually dispatch worker agents and record their outcomes

The orchestrator toolkit should be **distinct** from the worker-facing task toolkit.

That separation matters because the two roles have different authority:

- **worker agents** should get a narrow, task-scoped interface
- **orchestrator agents** should get a global, higher-authority interface

This should be enforced by toolkit design, not just by prompt wording.

---

## Review of the previous task-toolkit plan

After reviewing `plans/task_toolkit.md`, I think the main design adjustment is:

> anything resembling a global `planner` or `admin` mode should move out of the worker task toolkit and into a separate `OrchestratorToolkit`.

The worker toolkit plan was correct about the safe default surface:

- inspect current task
- inspect nearby run state
- attach notes and artifacts
- record structured task proposals
- avoid claim/complete/fail authority

But the earlier idea of optionally adding a `mode="planner"` to that same toolkit is weaker than a clean role split.

### Updated recommendation

- keep `TaskToolkit` **worker-focused**
- create a separate `OrchestratorToolkit` for global task control

That makes the authority boundary explicit in code and tests.

---

## What I reviewed

This plan builds directly on the work just completed and reuses the current task-system boundary.

I reviewed:

- `plans/task_toolkit.md`
- `plans/tasks.md`
- `aftk/tasks/manager.py`
- the current `aftk.tasks` package shape and APIs
- the existing toolkit implementation patterns already examined for the worker-toolkit plan
- the relevant Pydantic AI toolset/tool docs already examined for the worker-toolkit plan

The most important current fact is that the task system already has a clear authority center:

- `TaskManager` owns state transitions and persistence

That is the right thing for both toolkits to wrap.

---

## Role split: worker toolkit vs orchestrator toolkit

This is the core architectural distinction.

## Worker toolkit

The worker toolkit should be optimized for **doing a task**.

It should let a worker agent:

- inspect its current task
- inspect dependencies and run summaries when helpful
- attach notes and artifacts
- propose follow-up tasks safely

It should **not** let a worker agent:

- claim arbitrary tasks
- complete/fail/cancel arbitrary tasks
- freely mutate the task graph
- dispatch other workers

## Orchestrator toolkit

The orchestrator toolkit should be optimized for **running the workflow**.

It should let an orchestrator agent:

- inspect the whole run
- identify ready/blocked/failed work
- create and refine tasks and dependencies
- claim/requeue/cancel/finalize tasks
- review proposals produced by workers
- eventually dispatch workers and record outcomes

In short:

- worker toolkit = **task execution surface**
- orchestrator toolkit = **workflow control surface**

---

## Design principles

1. **Separate authority by toolkit, not by convention.**
   Worker and orchestrator capabilities should live in different toolkits.

2. **Keep `TaskManager` as the single source of truth.**
   The orchestrator toolkit should wrap manager APIs and adjacent helpers rather than reimplementing task semantics.

3. **Preserve the current Python-owned orchestration model.**
   This remains consistent with `plans/tasks.md`: workflow state lives in Python, Lean remains a semantic backend.

4. **Make all orchestrator tools sequential.**
   The task manager/store assume single-writer behavior in v1. Tool calls should not run concurrently by default.

5. **Use structured agent-facing failures.**
   Follow the existing toolkit pattern used by `CodingToolkit` and `AftkToolkit`.

6. **Prefer a small, composable first slice.**
   Start with full-run read tools and explicit task-control tools. Add worker dispatch later.

7. **Do not bury cross-toolkit task semantics in toolkit code.**
   If worker proposals or dispatch bookkeeping need shared schemas/helpers, put them in `aftk.tasks` or an adjacent task-domain module.

---

## Recommendation summary

Implement a separate orchestrator toolkit package:

```text
aftk/toolkits/
  orchestrator.py
  orchestrator/
    __init__.py
    _toolkit.py
    errors.py
    models.py
```

with a main class:

- `OrchestratorToolkit`

and agent-facing result envelopes:

- `OrchestratorToolSuccess`
- `OrchestratorToolFailure`
- `OrchestratorToolErrorInfo`

### Important relationship to the worker toolkit

The worker toolkit should remain narrow and safe.
The orchestrator toolkit should hold the global/planner/admin capabilities instead of overloading `TaskToolkit` with a broad planner mode.

---

## Proposed package shape

### Toolkit files

```text
aftk/toolkits/orchestrator.py                  # repository layout marker

aftk/toolkits/orchestrator/__init__.py        # public exports

aftk/toolkits/orchestrator/models.py          # tool input models + success/failure envelopes + run/task/admin views

aftk/toolkits/orchestrator/errors.py          # OrchestratorToolkitExecutionError + exception mapping

aftk/toolkits/orchestrator/_toolkit.py        # OrchestratorToolkit implementation

tests/python/test_orchestrator_toolkit.py     # schema/behavior tests
```

### Likely adjacent support modules

The orchestrator toolkit will probably want one or two small task-domain helpers that should **not** live only inside toolkit code.

Possible additions later:

```text
aftk/tasks/proposals.py     # shared proposal artifact schemas + extraction/apply helpers

aftk/tasks/workers.py       # worker-runner protocol(s) for orchestrator dispatch
```

I would avoid creating those until the toolkit implementation actually needs them, but the plan should leave room for them.

---

## Toolkit construction

## Recommended constructor

A good initial shape is:

```python
OrchestratorToolkit(
    manager: TaskManager,
    *,
    worker_runner: TaskWorkerRunner | None = None,
    read_only: bool = False,
    advanced: bool = False,
    id: str | None = None,
)
```

### Why this shape

- `manager` provides the authoritative task/run API
- `worker_runner` leaves room for future worker dispatch without forcing it into v1
- `read_only` matches existing toolkit conventions
- `advanced` leaves room for more powerful or lower-level orchestration operations later
- `id` matches the existing toolkit style and leaves room for durable execution compatibility later

### Expected default behavior

- basic read tools are always available
- mutation/lifecycle tools are disabled when `read_only=True`
- dispatch tools are exposed only when `worker_runner` is present
- especially sharp or low-level admin tools can be gated by `advanced=True`

---

## Naming and capability boundaries

## Tool naming

To make role boundaries obvious to the model and to humans, use a distinct prefix for orchestrator tools.

Recommended prefix:

- `orch_...`

Examples:

- `orch_run_summary`
- `orch_list_ready`
- `orch_add_task`
- `orch_claim_task`
- `orch_dispatch_task`

This keeps a clear separation from worker-facing `task_...` tools.

## Capability boundaries

Recommended role split:

- `task_...` tools: worker-safe, mostly scoped, no global workflow authority
- `orch_...` tools: global workflow authority, run-wide state, lifecycle control, proposal review, worker coordination

---

## Recommended v1 orchestrator tool surface

The first orchestrator toolkit should provide enough control to reason over and manage the run, but it does not need to launch workers yet.

## Read tools

| Tool | Mutates | Purpose |
|---|---:|---|
| `orch_run_summary` | no | Return run-wide counts, status buckets, and short task summaries. |
| `orch_task_table` | no | Return an ordered table/list view of tasks and scheduler status. |
| `orch_get_task` | no | Return full detail for one task, including dependencies, attempts, artifacts, and derived scheduler status. |
| `orch_list_ready` | no | Return ready tasks. |
| `orch_list_blocked` | no | Return blocked tasks. |
| `orch_list_running` | no | Return running tasks. |
| `orch_list_failed` | no | Return failed tasks. |
| `orch_list_terminal` | no | Return completed/failed/canceled tasks. |
| `orch_list_incomplete` | no | Return incomplete tasks. |
| `orch_validate_graph` | no | Re-run task-graph validation and return a success summary. |

### Why these read tools matter

An orchestrator agent needs a run-global picture before it can plan or intervene.

These tools let it answer questions like:

- what work is ready now?
- what is blocked, and why?
- which tasks are repeatedly failing?
- which worker proposals still need review?

## Mutation and lifecycle tools

| Tool | Mutates | Purpose |
|---|---:|---|
| `orch_add_task` | yes | Add one task from a validated task spec. |
| `orch_add_tasks` | yes | Add a batch of tasks from validated task specs. |
| `orch_add_dependency` | yes | Add one dependency edge. |
| `orch_attach_note` | yes | Attach an orchestrator note to any task. |
| `orch_attach_artifact` | yes | Attach an artifact to any task. |
| `orch_claim_task` | yes | Claim a ready task for execution. |
| `orch_complete_task` | yes | Mark a running task completed with summary/artifacts/metadata. |
| `orch_fail_task` | yes | Mark a running task failed with error message and optional artifacts. |
| `orch_cancel_task` | yes | Cancel a pending or running task. |
| `orch_requeue_task` | yes | Requeue a failed task. |

### Why these lifecycle tools belong here

Unlike worker agents, the orchestrator agent is the right place to hold lifecycle authority.

These tool calls correspond closely to current `TaskManager` methods and fit the intended ownership model:

- the orchestrator decides what should run
- the orchestrator decides what to retry
- the orchestrator decides how to react to failures and proposals

---

## Proposal-review and proposal-application tools

The worker toolkit plan proposed that workers should record follow-up task proposals as artifacts instead of mutating the graph directly.

That means the orchestrator toolkit needs a matching review/apply surface.

## Recommended proposal tools

| Tool | Mutates | Purpose |
|---|---:|---|
| `orch_list_proposals` | no | List unresolved task-proposal artifacts across the run. |
| `orch_get_proposal` | no | Return one proposal artifact in detail. |
| `orch_apply_proposal` | yes | Validate and apply one proposal artifact to the task graph. |
| `orch_reject_proposal` | yes | Record that a proposal was reviewed and rejected. |

### Why proposal application should be explicit

This preserves the intended authority flow:

1. worker notices follow-up work
2. worker records a structured proposal
3. orchestrator reviews the proposal
4. orchestrator decides whether to apply it

That keeps graph mutation auditable and intentional.

## Shared artifact convention

To make worker/orchestrator interop clean, define a stable proposal artifact convention.

A good initial direction is:

- artifact kind: `task_proposal_batch`
- artifact value: validated payload containing one or more proposed `TaskSpec`-like entries, optional dependency links, rationale, and source-task metadata

This schema likely belongs in the task domain layer rather than only inside one toolkit.

---

## Worker-dispatch tools: recommended later phase

Eventually the orchestrator is supposed to orchestrate worker agents.

That suggests a future second layer of tools that delegate to an injected worker runner.

## Recommended dispatch tools

| Tool | Mutates | Purpose |
|---|---:|---|
| `orch_dispatch_task` | yes | Claim a task, run a worker on it, and record the result. |
| `orch_dispatch_next_ready` | yes | Select the next ready task by current scheduler order, dispatch a worker, and record the result. |
| `orch_dispatch_ready_until_blocked` | yes | Repeatedly dispatch ready tasks until no more are ready or a limit is reached. |

### Important v1 simplification

If dispatch is implemented, the first version should be:

- **single-process**
- **single-writer**
- **synchronous from the orchestrator toolkit’s point of view**

That means one tool call can:

1. select or accept a task id
2. claim the task through `TaskManager`
3. invoke the worker runner
4. receive a `TaskExecutionResult`
5. complete/fail/cancel the task via `TaskManager`
6. return the final task record/view

This is much simpler than introducing:

- async work queues
- distributed leases
- long-lived external task tickets
- multi-writer locking

Those can come later if needed.

---

## Worker-runner seam

If dispatch tools are added, the orchestrator toolkit should not hardcode how workers are created.

Instead, it should depend on an injected protocol, e.g. conceptually:

```python
class TaskWorkerRunner(Protocol):
    async def run_task(... ) -> TaskExecutionResult: ...
```

The exact signature can be finalized later, but it should be designed so the runner can:

- construct the worker agent
- attach `TaskToolkit(current_task_id=...)`
- optionally attach `CodingToolkit` and `AftkToolkit`
- run the worker
- return a `TaskExecutionResult`

### Why this seam matters

It keeps the orchestrator toolkit focused on workflow control while allowing different worker execution strategies later:

- local direct worker-agent execution
- profile-based worker selection
- different model/tool configurations by task kind
- eventually externalized/distributed runners

---

## Agent-facing models

## Result envelopes

Follow the existing toolkit pattern with a separate public envelope type for this toolkit.

Define in `aftk/toolkits/orchestrator/models.py`:

- `OrchestratorToolErrorInfo`
- `OrchestratorToolSuccess`
- `OrchestratorToolFailure`
- `OrchestratorToolResult`

Suggested shared fields:

- `ok: Literal[True/False]`
- `tool: str`
- `data: Any`
- `error.kind`
- `error.message`
- `error.retryable`
- `error.suggested_action`
- `error.details`

## Input models

Recommended initial inputs:

- `OrchTaskIdInput`
- `OrchTaskListInput`
- `OrchAddTaskInput`
- `OrchAddTasksInput`
- `OrchAddDependencyInput`
- `OrchTaskNoteInput`
- `OrchTaskArtifactInput`
- `OrchClaimTaskInput`
- `OrchCompleteTaskInput`
- `OrchFailTaskInput`
- `OrchCancelTaskInput`
- `OrchRequeueTaskInput`
- `OrchProposalIdInput`
- later: `OrchDispatchTaskInput`

These should be explicit Pydantic models with good parameter descriptions, matching the style of the existing toolkits.

## Output views

The orchestrator toolkit should return richer run-global views than the worker toolkit.

Recommended views:

- `OrchestratorTaskSummaryView`
- `OrchestratorTaskDetailView`
- `OrchestratorRunSummaryView`
- `OrchestratorProposalView`
- later: `OrchestratorDispatchResultView`

These can include:

- task id / kind / title
- lifecycle status
- derived scheduler status
- priority
- dependency ids and dependency summaries
- attempts and last error
- artifact counts or selected artifact summaries
- proposal-review metadata
- run-wide counts by status bucket

---

## Error-handling strategy

This toolkit should follow the same broad error pattern as the existing toolkits and the planned worker toolkit.

## Recommendation

1. Pydantic AI schema validation handles malformed arguments automatically.
2. task/orchestration/domain errors become structured `OrchestratorToolFailure` results.
3. unknown exceptions become a generic internal failure envelope.

## Why structured failures are especially important here

The orchestrator agent will make stateful decisions based on these results.

It needs inspectable, machine-readable failures such as:

- task not found
- invalid transition
- duplicate task id
- graph cycle would be introduced
- proposal not found
- proposal already applied
- worker runner unavailable
- dispatch failed

Those are workflow facts, not just generic exceptions.

## Suggested exception mapping

Create `OrchestratorToolkitExecutionError` and `failure_from_exception()` in `aftk/toolkits/orchestrator/errors.py`.

Suggested mappings:

- `TaskNotFoundError` -> `task_not_found`
- `TaskTransitionError` -> `invalid_transition`
- `TaskConflictError` -> `task_conflict`
- `MissingDependencyError` -> `missing_dependency`
- `TaskCycleError` -> `cycle_detected`
- `TaskMappingError` / `TaskGraphError` -> `graph_error`
- proposal lookup failures -> `proposal_not_found`
- proposal re-application conflicts -> `proposal_conflict`
- missing worker runner -> `worker_runner_unavailable`
- worker dispatch failure -> `worker_dispatch_failed`
- fallback -> `orchestrator_tool_internal_error`

### Suggested details payloads

Where possible, include structured details such as:

- `task_id`
- `dependency_id`
- `run_id`
- `status`
- `scheduler_status`
- `proposal_id`
- `worker_name`
- `advanced`
- `read_only`

## `ModelRetry` guidance

Use `ModelRetry` sparingly.

Recommended default:

- rely on Pydantic AI’s normal schema-validation retries for malformed arguments
- return structured `OrchestratorToolFailure` for task-state, graph-state, and dispatch-state problems

That is the best match for the repository’s current toolkit style.

---

## Pydantic AI design notes

## Implementation pattern

Implement `OrchestratorToolkit` as a `WrapperToolset[Any]` that wraps one or more `FunctionToolset[Any]`, matching the repo’s existing toolkit pattern.

Suggested internal structure:

- `_build_read_toolset()`
- `_build_control_toolset()`
- `_build_proposal_toolset()`
- `_build_dispatch_toolset()`
- `_register(...)`
- `_normalize_result(...)`

## Sequential execution

Set `sequential=True` on all orchestrator toolsets.

The Pydantic AI docs make it clear that tools can otherwise run concurrently. That is the wrong default for a single-writer task manager and especially wrong once dispatch enters the picture.

## Metadata

Attach tool metadata similarly to the existing toolkits.

Suggested metadata:

```python
{
  "source": "orchestrator",
  "layer": "task_run",
  "mutates": True,
  "advanced": False,
  "dispatch": False,
  "role": "orchestrator",
}
```

At minimum, include:

- `source`
- `layer`
- `mutates`
- `advanced`
- `role`
- for dispatch tools: `dispatch`

## Dynamic tool preparation

The Pydantic AI docs make `prepare` and prepared/filtering toolsets available.

Likely later uses here:

- hide dispatch tools when no `worker_runner` is injected
- hide proposal tools when no proposals exist
- hide destructive/admin tools when orchestration policy disables them for a run step

For v1, constructor-time filtering is enough.

## Approval wrappers

If we later want human review over high-impact orchestration actions, prefer Pydantic AI approval wrappers around orchestrator tools rather than building a bespoke approval subsystem inside the toolkit.

Good candidates later:

- bulk task creation
- proposal application
- cross-run repair actions
- cancellation of running work

---

## Relationship to task-manager helpers

The orchestrator toolkit should wrap existing `TaskManager` methods where possible.

That said, a few small task-domain helpers may become worth adding beneath the toolkit for clarity.

Possible future helper methods or modules:

- `claim_next_ready_task()` convenience helper
- proposal extraction/apply helpers
- worker-runner protocol(s)
- dispatch bookkeeping helpers

These should live in the task/orchestration domain layer, not as hidden toolkit-only logic, if they become nontrivial.

---

## Integration with the agent stack

## Default recommendation

Do **not** add `OrchestratorToolkit` to `aftk.app.build_agent()` by default.

Reasons:

- most agents are not orchestrators
- the toolkit requires a live task manager
- optional worker dispatch requires additional injected runtime state

## Recommended composition pattern

Orchestrator runs should compose toolsets explicitly, for example:

```python
[
  CodingToolkit(...),
  AftkToolkit(...),
  OrchestratorToolkit(manager, worker_runner=runner),
]
```

That gives the orchestrator agent:

- project/global context from coding and AFTK tools
- workflow authority from the orchestrator toolkit

## Possible future helper

If orchestration becomes common, add a helper such as:

- `build_orchestrator_agent(...)`

But that should come after the toolkit API stabilizes.

---

## Recommended implementation phases

## Phase 1: separate the role boundary in planning

Clarify the intended split:

- `TaskToolkit` is worker-safe
- `OrchestratorToolkit` is global/admin/orchestration-safe

This phase is mostly conceptual but important because it should guide the implementation of both toolkits.

### Phase 1 success criteria

- the worker-toolkit plan is interpreted as worker-scoped only
- the orchestrator-toolkit plan owns the former global/planner/admin surface

---

## Phase 2: models and error mapping

Implement:

- `aftk/toolkits/orchestrator/models.py`
- `aftk/toolkits/orchestrator/errors.py`
- public exports and layout markers

Deliverables:

- success/failure envelopes
- input models
- run/task/proposal views
- exception-mapping helpers

### Phase 2 success criteria

- models serialize cleanly
- task manager/domain exceptions map to stable error kinds
- internal failures map to a generic orchestrator-tool failure

---

## Phase 3: read + lifecycle control tools

Implement `OrchestratorToolkit` with:

- run-global read tools
- task creation/dependency tools
- lifecycle tools (`claim`, `complete`, `fail`, `cancel`, `requeue`)
- note/artifact attachment

### Phase 3 success criteria

- schemas and metadata are exposed correctly to a `TestModel`
- all tools are sequential
- lifecycle mutations persist in manager state
- graph/state errors come back as structured failures

---

## Phase 4: proposal review and apply

Implement:

- proposal artifact conventions if needed
- `orch_list_proposals`
- `orch_get_proposal`
- `orch_apply_proposal`
- `orch_reject_proposal`

### Phase 4 success criteria

- worker-produced proposals can be listed and reviewed
- proposal application creates real tasks/dependencies through the task manager
- proposal rejection is recorded cleanly and idempotently

---

## Phase 5: worker dispatch integration

Add the injected worker-runner seam and dispatch tools:

- `orch_dispatch_task`
- `orch_dispatch_next_ready`
- optionally `orch_dispatch_ready_until_blocked`

### Phase 5 success criteria

- dispatch can claim a task, run a worker, and record the result
- failure paths are reflected in task state cleanly
- no new store/protocol architecture is required for the first slice

---

## Testing plan

Add `tests/python/test_orchestrator_toolkit.py`.

## Tests to include

### 1. Schema and exposure tests

Check that:

- expected `orch_...` tools are exposed
- tools are sequential
- metadata is correct
- dispatch tools appear only when a worker runner is injected
- read-only mode hides mutating tools

### 2. Read behavior tests

Check that:

- run summary counts are correct
- ready/blocked/failed listings are correct
- detailed task views include derived scheduler status
- graph validation success/failure is reported properly

### 3. Lifecycle mutation tests

Check that:

- `orch_claim_task` works only for ready tasks
- `orch_complete_task` updates attempts and artifacts
- `orch_fail_task` records error details
- `orch_requeue_task` respects `max_attempts`
- `orch_cancel_task` enforces valid transitions

### 4. Graph mutation tests

Check that:

- adding tasks works
- duplicate task ids return structured failures
- adding a bad dependency returns a graph-related failure
- cycle creation is rejected cleanly

### 5. Proposal workflow tests

Check that:

- proposal artifacts are listed correctly
- valid proposals can be applied
- invalid or duplicate proposals return structured failures
- rejection bookkeeping is stable

### 6. Dispatch tests with a fake worker runner

Check that:

- dispatch claims the task and records a completion result
- worker failure records a failed task
- runner absence produces a structured failure
- repeated dispatch obeys current task status and scheduler rules

### 7. Role-separation tests

Check that:

- worker `TaskToolkit` does not expose `orch_...` tools
- orchestrator `OrchestratorToolkit` exposes the global control surface
- capability separation is enforced by code, not just prompts

---

## Open questions

1. **Should `TaskToolkit` keep any planner mode at all?**
   My recommendation: no broad planner mode; keep it worker-oriented.

2. **What exact proposal artifact schema should workers emit?**
   This likely deserves a shared task-domain schema rather than toolkit-local ad hoc JSON.

3. **Should dispatch be synchronous at first or return a ticket/lease object?**
   My recommendation: synchronous first.

4. **Should the orchestrator agent itself directly call `orch_complete_task` / `orch_fail_task`, or should those mostly be internal to dispatch helpers?**
   My recommendation: expose them, but use dispatch helpers when possible.

5. **Do we want separate orchestrator profiles later?**
   For example, read-only observer vs full admin orchestrator. The constructor shape should leave room for this.

6. **Do proposal application and bulk graph mutation need approval by default?**
   Not in v1, but they should be easy to wrap with Pydantic AI approval tooling.

---

## Recommended first deliverable

The best first slice is:

1. create `OrchestratorToolkit`
2. expose run-global read tools and basic lifecycle tools
3. verify schema/metadata exposure with `TestModel`
4. call `orch_list_ready`, `orch_claim_task`, and `orch_complete_task`
5. verify manager state changes correctly
6. verify invalid transitions return `OrchestratorToolFailure`

That will prove the most important design choice:

- workers and orchestrators get different task-system authority surfaces
- task state remains centrally managed by `TaskManager`
- the orchestrator agent can reason over and control the workflow without collapsing the worker safety boundary

---

## Summary

The orchestrator toolkit should be a **separate, global-authority toolkit** layered on top of `TaskManager`.

It should exist alongside, not inside, the worker task toolkit.

### Worker toolkit

- narrow
- task-scoped
- safe
- notes/artifacts/proposals

### Orchestrator toolkit

- global
- workflow-controlling
- lifecycle-aware
- proposal-reviewing
- eventually worker-dispatching

That split is cleaner, safer, and more aligned with the architecture described in `plans/tasks.md` and the worker-toolkit plan.
