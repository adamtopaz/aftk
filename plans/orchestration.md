# Plan: orchestration architecture for worker and orchestrator agents

## Goal

Capture the current orchestration design for the task system, including:

- why orchestration lives in Python
- how the task system is meant to interact with agents
- why worker agents and orchestrator agents need different task toolkits
- which authority belongs to each role
- the main design decisions behind `plans/task_toolkit.md` and `plans/orchestrator_toolkit.md`

This document is intended as a synthesis of:

- `plans/tasks.md`
- `plans/task_toolkit.md`
- `plans/orchestrator_toolkit.md`

and should be treated as the higher-level orchestration design note tying those plans together.

---

## Core architectural decision

The orchestration layer for autoformalization should live in **Python**, not Lean.

That decision comes from the architecture described in `plans/tasks.md`:

- tasks, scheduling, retries, persistence, and orchestration are workflow concerns
- the current agents already live in Python using `pydantic-ai`
- Lean is still crucial, but as a **semantic backend**, not as the owner of workflow state

So the intended split is:

- **Python owns workflow state and orchestration**
- **Lean/AFTK provides semantic facts and queries**

Examples of Lean/AFTK responsibilities:

- declaration/reference dependency information
- source-level query data
- goal and tactic-state information
- knowledge-base and informal-layer information

Examples of Python orchestration responsibilities:

- represent tasks and task runs
- compute ready vs blocked work
- persist run state
- claim/retry/cancel/finalize work
- decide when workers should run
- decide whether to accept worker proposals

---

## Current task-system foundation

The orchestration design assumes the current `aftk.tasks` package remains the task-domain foundation.

Important current pieces:

- `TaskSpec`, `TaskRecord`, `TaskRunState`
- lifecycle status and derived scheduler status
- dependency validation and cycle detection
- file-backed and in-memory run stores
- `TaskManager` as the central state-transition API
- orchestration helpers like `execute_next_ready_task`
- prompt/planner helpers

The most important existing design fact is:

> `TaskManager` is the single source of truth for task state transitions and persistence.

Any future toolkit or agent integration should wrap `TaskManager`, not bypass or duplicate it.

---

## Orchestration roles

The main orchestration design decision is to distinguish between two agent roles:

1. **worker agents**
2. **orchestrator agents**

These are not just different prompts for the same capability set. They represent different authority levels and should therefore receive different toolkits.

### Worker agent

A worker agent is responsible for **doing a task**.

Typical worker responsibilities:

- inspect the current task
- inspect dependencies and nearby run context
- use coding/AFTK tools to do the task
- attach notes and artifacts
- suggest follow-up work

A worker agent should generally **not** be allowed to:

- claim arbitrary tasks
- finalize arbitrary tasks
- mutate the whole task graph freely
- dispatch other workers
- take over run-wide scheduling

### Orchestrator agent

An orchestrator agent is responsible for **running the workflow**.

Typical orchestrator responsibilities:

- inspect the whole task run
- decide what should run next
- create and refine task graphs
- claim, requeue, cancel, or finalize tasks
- review worker proposals
- eventually dispatch worker agents

This is a broader and more powerful role than the worker role.

---

## Why the worker/orchestrator split should be enforced in code

A central design decision in the toolkit plans is:

> role boundaries should be enforced by toolkit design, not only by prompt wording.

Why this matters:

- prompts are soft constraints
- tool availability is a hard constraint
- if a worker agent has graph-admin tools, then the worker is effectively also an orchestrator
- testing and auditing are much easier when authority is reflected in distinct APIs

So the recommended design is:

- **worker task toolkit** for worker-safe task interactions
- **orchestrator toolkit** for global workflow control

This is cleaner than a single large task toolkit with all capabilities exposed behind informal conventions.

---

## Main design decision from `plans/task_toolkit.md`

The worker-facing `TaskToolkit` should be **narrow, task-scoped, and safe by default**.

### Intended worker-toolkit behavior

The worker toolkit is meant to let an agent:

- inspect the current task
- inspect nearby run summaries
- attach notes and artifacts
- record structured task proposals

The worker toolkit is **not** meant to let the model take over scheduling.

### Why

This follows the core decision from `plans/tasks.md`:

- orchestration stays in Python control
- the model should help perform selected work, not freely manage the workflow

### Recommended worker-safe tool surface

Representative tools from the worker plan:

- `task_current`
- `task_get`
- `task_run_summary`
- `task_list_ready`
- `task_list_blocked`
- `task_add_note`
- `task_add_artifact`
- `task_propose_tasks`

### Important exclusion

The worker toolkit should not expose, by default:

- `task_claim`
- `task_complete`
- `task_fail`
- broad graph mutation
- direct run-state replacement
- arbitrary dependency rewrites

That exclusion is intentional, not accidental.

---

## Main design decision from `plans/orchestrator_toolkit.md`

The orchestrator-facing `OrchestratorToolkit` should be a **separate global-authority toolkit**.

This plan refines the earlier task-toolkit discussion in one important way:

> global planner/admin capabilities should live in a separate orchestrator toolkit, not inside the worker task toolkit.

### Intended orchestrator-toolkit behavior

The orchestrator toolkit is meant to let an orchestrator agent:

- inspect the full run
- create and refine tasks and dependencies
- claim and finalize tasks
- handle retries and cancellations
- review and apply worker proposals
- later, dispatch worker agents

### Representative orchestrator tool surface

Representative tools from the orchestrator plan:

- `orch_run_summary`
- `orch_task_table`
- `orch_get_task`
- `orch_list_ready`
- `orch_list_blocked`
- `orch_list_failed`
- `orch_add_task`
- `orch_add_tasks`
- `orch_add_dependency`
- `orch_claim_task`
- `orch_complete_task`
- `orch_fail_task`
- `orch_cancel_task`
- `orch_requeue_task`
- later: `orch_list_proposals`, `orch_apply_proposal`, `orch_dispatch_task`

The orchestrator toolkit is where lifecycle and graph-level authority belongs.

---

## How these two plans fit together

The cleanest current interpretation of the two toolkit plans is:

- `TaskToolkit` = **worker-facing execution toolkit**
- `OrchestratorToolkit` = **global workflow-control toolkit**

### Important clarification

`plans/task_toolkit.md` left room for a possible broader planner/advanced mode inside `TaskToolkit`.

After the later orchestrator-toolkit analysis, the cleaner long-term direction is:

- keep `TaskToolkit` worker-focused
- move broad planner/admin/global capabilities into `OrchestratorToolkit`

So if there is ever any tension between the two files, the intended direction should be:

> broad workflow authority belongs in `OrchestratorToolkit`, not in the default worker toolkit.

---

## Task proposals: why workers record them instead of applying them

A major design decision connecting both plans is the proposal flow.

### Decision

Workers should be able to record structured follow-up proposals, but should not directly mutate the task graph by default.

### Why

This preserves a clean authority flow:

1. worker notices follow-up work
2. worker records a structured proposal artifact
3. orchestrator reviews the proposal
4. orchestrator decides whether to apply it to the graph

### Benefits

- graph mutation remains intentional and auditable
- worker mistakes are easier to contain
- human review is easier to add later
- model-suggested planning is preserved without handing the model scheduler authority

### Consequence for toolkit design

This implies a matching orchestrator surface for proposal review and application.

That is why the orchestrator plan includes tools like:

- `orch_list_proposals`
- `orch_get_proposal`
- `orch_apply_proposal`
- `orch_reject_proposal`

---

## Why both toolkits should wrap `TaskManager`

Another important decision is to keep toolkit code thin.

### Decision

Both toolkits should wrap existing task-domain logic rather than reimplementing task behavior.

### Why

`TaskManager` already centralizes:

- lifecycle transition validation
- persistence after mutation
- graph validation
- task lookup and listing
- artifact/note attachment
- retry/requeue semantics

If toolkit code duplicated these rules, it would create:

- drift between tool behavior and Python behavior
- harder debugging
- duplicated tests
- inconsistent workflow semantics

So the intended layering is:

- `aftk.tasks` owns domain logic
- `aftk.toolkits.tasks` and `aftk.toolkits.orchestrator` provide agent-facing wrappers

---

## Error-handling design

Both toolkit plans deliberately follow the existing repository pattern used by:

- `CodingToolkit`
- `AftkToolkit`

### Decision

Tools should return structured success/failure envelopes instead of exposing raw exceptions to agents.

### Why

Most task-related failures are workflow/domain facts, not catastrophic internal crashes.

Examples:

- task not found
- invalid transition
- duplicate task id
- graph cycle would be introduced
- task is blocked
- worker runner unavailable
- dispatch failed

These are useful pieces of information for an agent to inspect and respond to.

### Consequence

Both plans recommend toolkit-specific envelopes such as:

- `TaskToolSuccess` / `TaskToolFailure`
- `OrchestratorToolSuccess` / `OrchestratorToolFailure`

with stable error kinds like:

- `task_not_found`
- `invalid_transition`
- `task_conflict`
- `cycle_detected`
- `graph_error`
- `proposal_not_found`
- `worker_dispatch_failed`

This makes model behavior, tests, and logs more reliable.

---

## Why `ModelRetry` is not the primary task-error mechanism

The toolkit plans also made a deliberate decision about how to use Pydantic AI’s retry model.

### Decision

- let Pydantic AI handle schema/argument validation retries normally
- return structured tool failures for task-state and orchestration-state errors
- use `ModelRetry` sparingly

### Why

Schema problems are good candidates for retry:

- wrong type
- missing field
- invalid argument shape

But many task errors are state facts rather than argument problems:

- the task is blocked
- the task is already terminal
- the dependency would create a cycle
- a proposal was already applied

Those are better exposed as structured failures than as retry prompts.

---

## Why all task-related and orchestrator-related tools should be sequential

The Pydantic AI docs allow tool calls to execute concurrently unless marked sequential.

### Decision

All task and orchestrator toolsets should be registered with `sequential=True`.

### Why

The current task layer is designed around:

- a single task manager authority
- file-backed persistence
- single-writer assumptions in v1

Concurrent task mutations would complicate:

- state consistency
- debugging
- persistence guarantees
- claim/finalize ordering

So sequential execution is the right default for the current architecture.

---

## Why tool naming should reflect role

The plans recommend different tool prefixes:

- worker tools: `task_...`
- orchestrator tools: `orch_...`

### Why

This helps with:

- capability clarity for the model
- human readability
- avoiding collisions
- testing expected surfaces
- future filtering/approval rules

The naming choice is part of the authority boundary.

---

## Why neither toolkit should be attached to every agent by default

Both plans recommend explicit composition rather than automatic inclusion in `aftk.app.build_agent()`.

### Why

These toolkits require runtime context that many generic agents will not have:

- a live `TaskManager`
- sometimes a `current_task_id`
- later, possibly a worker runner

So the preferred composition is explicit.

### Worker-agent example

A task worker would likely use something like:

```text
CodingToolkit + AftkToolkit + TaskToolkit(current_task_id=...)
```

### Orchestrator-agent example

An orchestrator would likely use something like:

```text
CodingToolkit + AftkToolkit + OrchestratorToolkit(manager, ...)
```

This keeps the generic agent builder decoupled from orchestration runtime state.

---

## Worker dispatch: planned later, not first

The orchestrator plan includes eventual worker dispatch, but not as the first implementation milestone.

### Decision

Start with:

- run-global inspection
- task/lifecycle control
- proposal review/application

and add dispatch later.

### Why

Dispatch introduces a second layer of complexity:

- worker construction
- toolset composition
- result normalization
- multi-agent coordination
- additional failure modes

The first orchestration slice should prove the authority model and task-control surface before adding worker execution machinery.

---

## Why dispatch should use an injected runner seam

When dispatch is added, the orchestrator plan recommends an injected worker-runner interface rather than hardcoding worker execution into the toolkit.

### Why

This keeps responsibilities separate:

- orchestrator toolkit decides **when** and **what** to run
- worker runner decides **how** a worker is constructed and executed

That leaves room for later variation:

- different worker profiles by task kind
- different models/toolsets for different work
- local direct execution first
- eventual external or distributed execution later

This is a useful seam without prematurely committing to a heavy runtime architecture.

---

## Shared task-domain helpers likely needed later

The toolkit plans suggest that some concepts should become shared task-domain helpers rather than staying toolkit-local.

Likely candidates:

- proposal artifact schemas and apply/extract helpers
- worker-runner protocol(s)
- possibly convenience helpers for dispatch/claim-next-ready operations

These should live under `aftk.tasks` or an adjacent task-domain module if they become substantial, since they are orchestration-domain concepts rather than purely toolkit concerns.

---

## Current implementation guidance

If implementation begins from these plans, the intended order should be:

1. keep `TaskToolkit` worker-scoped
2. implement `OrchestratorToolkit` separately for global authority
3. use structured success/failure envelopes for both
4. keep all task-related tools sequential
5. keep `TaskManager` as the single state authority
6. treat worker proposals as reviewable artifacts
7. add worker dispatch only after the read/control/proposal workflow is solid

---

## Decision log

### Decision 1: orchestration lives in Python

Reason:
- agents are in Python
- workflow state is operational, not Lean-semantic
- existing architecture already preserves a Python/Lean boundary

### Decision 2: `TaskManager` remains the authority center

Reason:
- it already owns transitions, persistence, and validation
- toolkits should adapt, not duplicate, task semantics

### Decision 3: split worker and orchestrator capabilities into separate toolkits

Reason:
- they have different authority levels
- role separation should be enforced by code, not only prompts

### Decision 4: keep the worker toolkit narrow and task-scoped

Reason:
- worker agents should execute work, not own the scheduler
- note/artifact/proposal support is useful without giving away global control

### Decision 5: give lifecycle and graph authority to the orchestrator toolkit

Reason:
- claim/fail/complete/requeue/cancel are workflow-control actions
- this is the right place for planner/admin capabilities

### Decision 6: workers propose, orchestrators apply

Reason:
- preserves auditability and authority boundaries
- gives a safe route for model-suggested graph evolution

### Decision 7: use structured failure envelopes

Reason:
- task/orchestration errors are workflow facts
- consistent with the repo’s existing toolkit style

### Decision 8: make all task/orchestrator tools sequential

Reason:
- current task persistence/model assumes single-writer v1 behavior
- avoids concurrency complexity before it is needed

### Decision 9: add dispatch later through an injected runner seam

Reason:
- keeps the first orchestration slice simple
- avoids overcommitting to a worker execution backend too early

---

## Summary

The orchestration design now has a clear intended shape:

- **Python owns task workflow state and orchestration**
- **Lean/AFTK remains the semantic backend**
- **`TaskManager` is the single source of task truth**
- **worker agents get a narrow, task-scoped toolkit**
- **orchestrator agents get a separate global-control toolkit**

In practical terms:

### Worker side

- inspect the current task
- use coding/AFTK tools to do work
- attach notes and artifacts
- propose follow-up tasks safely

### Orchestrator side

- inspect the full run
- manage tasks and lifecycle transitions
- review and apply proposals
- eventually dispatch workers

This is the intended authority model for future orchestration work in this repository.
