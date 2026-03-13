# Plan: initial task management layer for autoformalization

## Goal

Build a first task-management layer for the autoformalization workflow that can:

- represent work items as explicit tasks
- track dependencies between tasks
- track task lifecycle and attempts
- persist and resume task state across runs
- drive one or more Python agents over ready tasks
- reuse the existing Lean server/client/toolkit stack for semantic queries instead of re-implementing them

The main architectural recommendation is:

> implement the task system in **Python**, not Lean, and treat Lean as the semantic backend that the task system consults.

---

## What I inspected

I reviewed the current architecture and relevant implementation seams in:

- `README.md`
- `docs/architecture.md`
- `docs/roadmap.md`
- `docs/server/overview.md`
- `docs/server/protocol.md`
- `aftk/app.py`
- `aftk/client.py`
- `aftk/toolkits/aftk/_toolkit.py`
- `aftk/toolkits/aftk/models.py`
- `AFTK/Informal/Dependencies.lean`

The main architectural signals are:

1. future automation/orchestration work is supposed to restart **on top of** the retained server/client boundary
2. the current agents already live in Python and are built with `pydantic-ai`
3. Lean already provides useful semantic/dependency queries that can feed a higher-level task system

---

## Recommendation summary

The initial task system should be a **Python-native orchestration layer**.

### Why Python should own the task layer

- The agents are already Python `pydantic-ai` agents.
- Task status, retries, scheduling, persistence, and orchestration are operational workflow concerns, not Lean semantic concerns.
- The repo docs explicitly frame future automation as a layer above the current public server/client interfaces.
- Lean already has a good role here: compute semantic facts and dependency views, then let Python consume them.

### Why Lean should not own v1

A Lean-first task system would force every orchestration change through:

- Lean data structures
- server protocol additions
- Python client wrappers
- agent-facing toolkit wrappers

That is too much cross-language coupling for a first experimental workflow layer.

---

## Design principles

1. **Python owns workflow state.**
   Tasks, attempts, scheduling, and persistence live in Python.

2. **Lean owns semantic facts.**
   The task layer asks Lean/AFTK for dependency and file/query information through the existing server/client boundary.

3. **Treat tasks as operational state, not canonical knowledge-base state.**
   Tasks should not become part of the canonical knowledge-base storage model.

4. **Prefer a small, transparent v1.**
   Start with a simple file-backed task store and a single-process manager.

5. **Derive scheduling state where possible.**
   Avoid storing redundant “ready vs blocked” data if it can be computed from dependency status.

6. **Do not build a generic workflow framework.**
   The first version should be a focused task layer for this repository’s autoformalization workflow.

7. **Avoid new Lean/server work unless the current boundary is clearly insufficient.**
   Reuse `AsyncAftkClient` and the current toolkits first.

---

## Scope for the first implementation

### In scope

- a Python task model
- task dependency edges
- task lifecycle/status tracking
- attempt history
- file-backed persistence and resume
- task-graph validation
- ready-task computation
- a small orchestrator API that selects and runs ready tasks
- integration with the current Python agent layer
- optional import of Lean-derived dependency information into the task graph

### Out of scope for v1

- a Lean-native task runtime
- a new server protocol for task storage
- distributed scheduling
- database-backed persistence
- complex multi-writer concurrency
- a general-purpose plugin/extensibility framework
- a large model-controlled task-editing surface

---

## Proposed package shape

A good starting point is a new Python package subtree under `aftk/`:

```text
aftk/
  tasks/
    __init__.py
    models.py       # Pydantic models and enums
    graph.py        # dependency validation and ready-set logic
    store.py        # persistence interface + file-backed implementation
    manager.py      # high-level state transitions and orchestration helpers
    planner.py      # task creation / expansion helpers for autoformalization
    prompts.py      # task-context rendering for agents
```

Optional later additions:

```text
    toolkit.py      # small Pydantic AI task toolset, if needed later
    reports.py      # summaries / debug rendering
```

Tests would live under `tests/python/`, for example:

```text
tests/python/
  test_task_models.py
  test_task_graph.py
  test_task_store.py
  test_task_manager.py
  test_task_orchestration.py
```

---

## Core data model

The task layer should distinguish between:

- **task specification**: what the work item is
- **task runtime state**: where it is in execution
- **task attempt history**: what happened when it was tried
- **task artifacts**: outputs, notes, file paths, and related metadata

### 1. Task identity

Use stable string ids, for example:

- `task-0001`
- `formalize.group.basic.definition`
- `prove.MyModule.my_theorem`

For v1, a string id is sufficient.
No need for a heavier typed id abstraction.

### 2. Task kind

Use a small machine-readable string field such as:

- `kind: str`

Examples for autoformalization-oriented tasks:

- `inspect_target`
- `gather_context`
- `formalize_reference`
- `draft_declaration`
- `repair_build_error`
- `validate_result`

The manager should not hardcode too much behavior by kind in v1.
The kind should mainly support filtering, prompting, and reporting.

### 3. Task payload

Each task needs structured task-specific input data.
A simple initial shape is:

- `title: str`
- `description: str | None`
- `payload: dict[str, Any]`
- `tags: list[str]`
- `priority: int`

Example payloads might include:

- target knowledge-base reference
- Lean module or declaration name
- file path
- source location
- expected output type
- notes from upstream planning

### 4. Dependency model

Use **hard dependency edges only** in v1:

- `depends_on: list[str]`

Semantics:

- a task may start only when all dependencies are completed successfully
- failed dependencies keep downstream tasks unavailable until a human or planner intervenes
- the graph must be acyclic

Defer soft dependencies, preference edges, and conditional branching until the basic system proves itself.

---

## Status model

A good v1 design is to store a small **lifecycle status** and derive scheduler views like “ready” and “blocked”.

### Stored lifecycle statuses

Recommended stored statuses:

- `pending`
- `running`
- `completed`
- `failed`
- `canceled`

### Derived scheduler views

Derived from lifecycle status + dependencies:

- `blocked`
- `ready`
- `running`
- `completed`
- `failed`
- `canceled`

This avoids inconsistencies like a task being stored as both `blocked` and `ready` after dependency edits.

### Suggested transition rules

Core transitions:

- `pending -> running`
- `running -> completed`
- `running -> failed`
- `running -> canceled`
- `failed -> pending` for explicit retry/requeue
- `pending -> canceled`

A manager method should validate transitions centrally rather than leaving that logic spread across callers.

---

## Attempt and artifact tracking

A task system needs more than a single status bit.

### Task attempt record

Each execution attempt should record at least:

- attempt number
- start time
- end time
- runner / agent id
- summary outcome
- error message if any
- optional structured metadata

This is useful for:

- retry control
- debugging
- prompt refinement
- later evaluation of agent behavior

### Task artifacts

Each task should be able to accumulate artifacts such as:

- output text
- file paths written or modified
- Lean declaration names created or changed
- related knowledge-base ids
- trace or run ids
- notes / annotations

For v1, artifacts can just be structured metadata attached to the task state.
No need for a large separate artifact subsystem.

---

## Persistence design

The task layer should use **simple file-backed persistence** first.

### Recommended v1 store

Use a JSON snapshot file under a task-run directory, for example:

```text
.aftk/tasks/<run_id>/state.json
.aftk/tasks/<run_id>/artifacts/
```

The exact path can be configurable, but the important design point is:

- task state is operational workspace state
- task state is not canonical knowledge-base content

### Why JSON snapshots first

- easy to inspect and debug
- consistent with the repository’s current preference for transparent storage
- very fast to implement
- good enough for a single-process experimental orchestrator

### Persistence rules

- load the whole run state at startup
- write atomically after each mutation
- keep schema explicit and versioned
- avoid append-only event sourcing in v1
- avoid SQLite unless the single-file snapshot becomes a real bottleneck

### Concurrency assumption

Assume **single writer** in v1.
If later we need multiple concurrent agents or external operators mutating the same run state, then we can add locking or move to a stronger store.

---

## Manager responsibilities

The main Python API should be a task manager object responsible for:

- creating a new task run
- loading an existing run
- adding tasks
- adding dependency edges
- validating the graph
- computing ready tasks
- claiming a task for execution
- recording attempt start/end
- marking a task completed / failed / canceled
- requeueing failed tasks
- attaching artifacts and notes
- persisting state after each mutation

It should also provide useful query helpers such as:

- `list_tasks()`
- `get_task(task_id)`
- `ready_tasks()`
- `blocked_tasks()`
- `terminal_tasks()`
- `incomplete_tasks()`

The manager should be the authoritative place for state-transition rules.

---

## Integration with the current AFTK stack

The task system should sit **above** the existing AFTK client/toolkit boundary.

### Existing surfaces to reuse first

- `AsyncAftkClient` in `aftk/client.py`
- `AftkToolkit` in `aftk/toolkits/aftk/_toolkit.py`
- existing coding tools
- existing informal dependency queries
- existing knowledge-base relationship/search queries

### Lean’s role in the task workflow

Lean should provide facts like:

- declaration/reference dependency rows
- knowledge-base relationships
- goal/tactic-state information
- hover / infoview / source-level context

Python should turn those facts into workflow decisions like:

- create a follow-up task
- block this task until dependencies succeed
- retry with new context
- spawn validation work

### Important v1 rule

Do **not** start by adding a new task protocol to `aftk_server`.
If we later discover a missing semantic query, add the narrowest possible Lean/server endpoint for that query only.

---

## Agent integration strategy

The safest first design is to keep the **task manager in control**, not the model.

### Recommended v1 control flow

1. Python task manager computes the ready set.
2. Python orchestrator selects one ready task.
3. Python constructs focused task context and prompt material.
4. The existing `pydantic-ai` agent runs against that one task.
5. Python records the result and updates the task graph.

This keeps scheduling deterministic and debuggable.

### Why not expose broad task editing to the agent first

If the model can freely mutate the task graph from day one, it becomes much harder to reason about:

- graph consistency
- reproducibility
- failure recovery
- evaluation
- operator oversight

So the default should be:

- the model works on a selected task
- Python orchestration code decides what happens to the graph

### Optional later step: a small task toolkit

If needed later, add a limited Pydantic AI task toolset exposing a narrow surface such as:

- get current task
- list ready tasks
- attach a note
- propose a subtask
- mark attempt result

But this should be a later step, not a prerequisite for the first implementation.

---

## Planning and task generation

The first version should support two ways to populate the graph.

### 1. Explicit seed tasks

Allow callers to create tasks directly from Python code or a small JSON spec.
This is the simplest path to a working end-to-end slice.

### 2. Lean-informed expansion

Add planner helpers that can derive or refine tasks using existing AFTK queries.
Examples:

- derive dependency edges from informal dependency results
- create validation subtasks after a drafting task completes
- create repair subtasks after a failed Lean build step
- attach upstream declaration/reference context to a task prompt

The important split is:

- the planner may consult Lean
- the planner still creates ordinary Python task records

---

## Proposed implementation phases

## Phase 1: core models and graph logic

Create the Python task package with:

- task models
- status enums
- attempt/artifact models
- graph validation
- ready/blocked computation

Deliverables:

- `aftk/tasks/models.py`
- `aftk/tasks/graph.py`
- unit tests for validation and ready-set computation

### Phase 1 success criteria

- tasks can be created and serialized
- invalid dependencies are rejected
- cycles are detected
- ready tasks are computed correctly from dependencies and status

---

## Phase 2: file-backed store and manager API

Implement:

- run-state container model
- JSON snapshot store
- manager methods for transitions and persistence
- atomic save behavior
- resume/load behavior

Deliverables:

- `aftk/tasks/store.py`
- `aftk/tasks/manager.py`
- persistence and resume tests

### Phase 2 success criteria

- a run can be created, saved, reloaded, and mutated safely
- transitions are centrally validated
- task attempts and artifacts survive reload

---

## Phase 3: minimal orchestration loop

Integrate the manager with the existing agent layer.

Recommended first behavior:

- select one ready task
- render task context into a prompt supplement
- run the existing agent once for that task
- record success/failure and artifacts
- move to the next ready task

Deliverables:

- `aftk/tasks/planner.py` or small orchestration helpers
- `aftk/tasks/prompts.py`
- tests using `pydantic_ai.models.test.TestModel`

### Phase 3 success criteria

- one end-to-end run can execute multiple dependent tasks in order
- failures are recorded cleanly
- successful completion unblocks downstream tasks

---

## Phase 4: Lean-informed task expansion

Add planner helpers that consult the existing AFTK client/toolkit layer.

Possible first helpers:

- create dependency edges from `informal_decl_deps` or `informal_ref_deps`
- enrich tasks with knowledge-base metadata and relationships
- generate validation/repair subtasks after agent output

This phase should still prefer the current public client/toolkit APIs over new server work.

### Phase 4 success criteria

- the task graph can be seeded or refined from real AFTK query results
- the Python task manager remains the single source of workflow truth

---

## Validation and testing plan

Because this is a Python-side orchestration layer, validation should primarily use the existing Python workflow:

- `uv run python -m unittest discover -s tests/python -v`
- `uv run pyright`
- `uv run ruff check`

### Tests to add

1. **Model tests**
   - required/optional field validation
   - JSON round-trips
   - schema-version handling

2. **Graph tests**
   - cycle detection
   - missing dependency rejection
   - ready/blocked computation
   - terminal task handling

3. **Manager tests**
   - valid/invalid transitions
   - retry/requeue behavior
   - artifact attachment
   - atomic persistence/load behavior

4. **Orchestration tests**
   - ready task selection order
   - downstream unblocking on success
   - downstream remaining blocked on failure
   - resume after partial completion

5. **AFTK integration tests**
   - planner helpers that consume real or fixture-backed AFTK results
   - narrow integration checks rather than broad end-to-end complexity at first

---

## Open design questions

These do not block the initial implementation, but should be answered as the first slice becomes concrete.

1. **Where should the run state live by default?**
   - project-root `.aftk/tasks/`
   - configurable output directory
   - Hydra output dir for one-shot runs

2. **What is the right first task granularity?**
   - one task per knowledge-base node
   - one task per Lean declaration
   - one task per repair/validation step

3. **Do we need multi-agent leases in v1?**
   - probably not
   - but the models should leave room for a future `claimed_by` or lease field

4. **How much task mutation should be model-driven?**
   - my recommendation: very little in v1

5. **Which Lean-derived dependency views are actually useful for autoformalization scheduling?**
   - declaration dependencies
   - reference dependencies
   - knowledge-base relationships
   - possibly new narrow queries later

---

## Recommended first deliverable

The best first milestone is a small vertical slice:

1. create a task run from an explicit Python/JSON seed
2. validate the dependency graph
3. compute ready tasks
4. run the existing agent on one selected task
5. record completion/failure plus artifacts
6. persist and reload the run
7. continue with the next ready task

That slice will prove the most important architectural decision:

- Lean provides semantic tools and facts
- Python owns workflow state and orchestration

If that works well, richer planning and Lean-informed task expansion can be added on top without changing the core boundary.

---

## Summary

The first task system should be:

- **Python-native**
- **file-backed and transparent**
- **single-process and simple**
- **built on the existing AFTK client/toolkit boundary**
- **controlled primarily by Python orchestration code rather than by the model**

That is the cleanest fit for the current repository architecture and the safest way to start rebuilding the automation layer.
