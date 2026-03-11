# Plan: task system for the autoformalization framework

## Goal

Implement a persistent Python task system that serves as the canonical project state for the autoformalization framework.
This task system should exist before the agent runtime is built, because the agent runtime should plan and report against explicit task state rather than inventing its own implicit memory.

## Why the task system comes first

The task system is the boundary between:

- long-lived project state
- short-lived agent runs

Without it, the framework would have no reliable answer to questions like:

- what work exists?
- what is ready right now?
- what is blocked, and why?
- what changed after a worker run?
- what happened before the last restart?

So the task system should be treated as infrastructure, not as an afterthought.

## Design requirements

The first version should satisfy these requirements.

1. **Persistent**
   - survives process restarts
   - can be inspected on disk
2. **Validated**
   - task records use Pydantic models
   - dependency invariants are checked on every write
3. **Graph-based**
   - tasks form a DAG
   - readiness is determined from dependencies plus local status
4. **Atomic enough for workers**
   - each task should be executable with local context
   - global decomposition belongs to the orchestrator, not the worker
5. **Auditable**
   - changes are recorded as events or immutable attempt/run records
   - worker outcomes remain inspectable after the fact
   - task attempts can be tied to detailed run logs, tool logs, and cost summaries
6. **Simple operational model**
   - v1 assumes one framework runner process at a time
   - no database should be required for the initial implementation

## Non-goals for v1

The first version does not need to provide:

- distributed locking across machines
- a full relational database backend
- multi-user collaborative editing of task state
- speculative parallel scheduling of many workers
- a public task-query language

Those can be added later if the basic framework proves out.

## Proposed on-disk layout

Store task state under the framework state root:

```text
.framework/
  tasks/
    state.json
    events.jsonl
    attempts/
      <attempt-id>.json
```

Here `.framework/` is generated runtime state in the project workspace, not the Python package directory `aftk/`.

Recommended meaning:

- `state.json`
  - the latest canonical snapshot of the task graph
  - fast to load on startup
- `events.jsonl`
  - append-only history of task mutations
  - useful for debugging and audit
- `attempts/<attempt-id>.json`
  - immutable record of a single worker attempt on a task

This gives a good balance for v1:

- snapshot for simple reload
- event log for history
- immutable attempt records for worker-level provenance

## Core data model

The task system should be implemented with Pydantic v2 models.

### Status model

Recommended task statuses:

- `planned`
- `ready`
- `in_progress`
- `blocked`
- `completed`
- `failed`
- `cancelled`

Recommended meaning:

- `planned`
  - known work that is not yet executable
  - usually waiting on dependencies
- `ready`
  - executable now
- `in_progress`
  - currently claimed by a worker attempt
- `blocked`
  - not executable because a blocker is known
- `completed`
  - acceptance criteria met
- `failed`
  - terminal for now; requires explicit orchestrator action to reopen or replace
- `cancelled`
  - no longer relevant

### Supporting value models

```text
ArtifactRef
  kind: "file" | "declaration" | "knowledgebase_node" | "source" | "other"
  value: str

Blocker
  kind: "task" | "information" | "resource" | "external"
  summary: str
  task_id: str | None

TaskNote
  author: str
  message: str
  timestamp: datetime
```

These are intentionally small and transport-friendly.

### Main task model

```text
Task
  id: str
  title: str
  description: str
  kind: str
  status: TaskStatus
  priority: "low" | "normal" | "high" | "urgent"
  acceptance_criteria: list[str]
  depends_on: list[str]
  blockers: list[Blocker]
  scope: list[ArtifactRef]
  context_summary: str | None
  notes: list[TaskNote]
  created_by: str
  updated_by: str
  current_attempt_id: str | None
  attempt_count: int
  created_at: datetime
  updated_at: datetime
```

Notes on the fields:

- `kind` should remain flexible in v1
  - e.g. `bootstrap`, `formalization`, `proof_repair`, `knowledge_extraction`, `validation`
- `acceptance_criteria` matters because it gives the worker and orchestrator a concrete completion target
- `scope` should point to the local area the worker is expected to inspect
- `context_summary` is a concise human/agent-oriented description, not a replacement for full source context

### Task creation and mutation models

The runner should never apply ad hoc dictionaries to the task graph.
Use explicit mutation models such as:

```text
TaskDraft
  title: str
  description: str
  kind: str
  priority: ...
  acceptance_criteria: list[str]
  depends_on: list[str]
  blockers: list[Blocker]
  scope: list[ArtifactRef]
  context_summary: str | None

TaskPatch
  task_id: str
  new_status: TaskStatus | None
  add_dependencies: list[str]
  remove_dependencies: list[str]
  blockers: list[Blocker] | None
  append_notes: list[str]
  context_summary: str | None
  priority: ... | None
```

The exact patch shape can be refined during implementation, but it should remain explicit and typed.

### Attempt record model

Worker execution should be captured separately from the task itself.

```text
TaskAttempt
  id: str
  task_id: str
  worker_kind: str
  status: "running" | "completed" | "partial" | "blocked" | "failed"
  started_at: datetime
  finished_at: datetime | None
  run_id: str | None
  report_path: str | None
  transcript_path: str | None
  llm_call_log_path: str | None
  tool_call_log_path: str | None
  usage_summary: dict[str, int | float | str] | None
  cost_summary: dict[str, int | float | str] | None
  summary: str | None
```

This keeps the task record compact while preserving per-attempt provenance.
The detailed logs themselves can live under `.framework/runs/`, while the attempt record keeps pointers and rollups.

### Graph snapshot model

```text
TaskState
  revision: int
  tasks: dict[str, Task]
  created_at: datetime
  updated_at: datetime
```

The `revision` field gives us a simple optimistic consistency marker and makes debugging much easier.

## ID strategy

Use stable human-readable task ids in v1, for example:

```text
task-0001
task-0002
```

Reasons:

- easier to read in logs
- easier to mention in orchestrator decisions and worker reports
- easier to inspect manually

If we later need richer ids, we can add a secondary UUID field without changing the public task references.

## Task invariants

The task service should enforce at least these invariants.

### Graph invariants

- every dependency id must exist
- the dependency graph must be acyclic
- self-dependencies are forbidden

### Status invariants

- `ready` tasks must have all dependencies completed
- `in_progress` tasks must have a current attempt id
- `completed` tasks must have all dependencies completed
- `blocked` tasks should carry at least one blocker entry
- terminal tasks (`completed`, `failed`, `cancelled`) should not be claimable

### Mutation invariants

- only the task service mutates `state.json`
- workers never write task state directly
- every successful mutation appends an event to `events.jsonl`
- every worker execution creates or updates a `TaskAttempt`
- task attempts should be linkable to detailed run telemetry and cost records

## Readiness semantics

The framework needs a clear answer to “what can be worked on next?”

A task should be considered **ready** when all of the following hold:

- its status is not terminal
- it is not explicitly blocked
- it is not already in progress
- all dependencies are completed

In practice, the task service should recompute readiness after every graph mutation.
This can be done by a normalization pass that updates tasks from `planned` to `ready` when their prerequisites are satisfied.

## Recommended service split

Implement the task system with a few small Python components.

### `tasks/models.py`

Owns the Pydantic models:

- `Task`
- `TaskDraft`
- `TaskPatch`
- `TaskAttempt`
- `TaskState`
- supporting enums and value objects

### `tasks/store.py`

Owns persistence:

- load/save `state.json`
- append to `events.jsonl`
- read/write attempt records
- manage simple filesystem locking if needed

### `tasks/service.py`

Owns domain logic:

- create tasks from drafts
- apply typed patches
- claim a ready task
- start and finish attempts
- recompute readiness
- validate graph invariants
- reopen, cancel, or replace tasks when necessary

### Optional `tasks/selectors.py`

Owns read-side queries such as:

- list ready tasks
- list blocked tasks
- topological ordering helpers
- descendants / dependents queries

This can be separated later if `service.py` grows too large.

## Claiming and execution flow

The task system should support this runner flow:

1. orchestrator selects a ready task id
2. runner calls `claim_task(task_id)`
3. task status becomes `in_progress`
4. a `TaskAttempt` is created
5. worker runs
6. runner stores the worker report, run/cost log references, and finishes the attempt
7. orchestrator decides how the task graph should change next
8. runner applies the orchestrator patch

The important detail is that a worker report does **not** directly mutate the graph.
It becomes an input to the orchestrator, which then proposes the next graph changes.

## Recovery behavior

Crashes and interrupted runs are guaranteed to happen eventually, so recovery should be designed in from the start.

Recommended v1 behavior on startup:

- load `state.json`
- inspect any `in_progress` tasks
- inspect their attempt records
- if no active runner owns them, mark them back to `ready` and append a recovery event

This is conservative and simple.
A more advanced lease-based ownership model can be added later if we actually start running multiple workers concurrently.

## Event log shape

The event log should be append-only JSON lines.
Suggested event kinds:

- `task_created`
- `task_patched`
- `task_claimed`
- `attempt_started`
- `attempt_finished`
- `task_recovered`
- `task_deleted` only if we truly need hard deletion

Prefer soft state transitions over hard deletion.
Keeping old tasks visible is much better for auditability.

## Manual inspection and operator ergonomics

Even if v1 has no polished UI, the task system should remain easy to inspect.

That means:

- use readable ids
- keep `state.json` reasonably legible
- keep attempt files small and focused
- avoid binary formats
- avoid making the event log the only place the current state can be understood

A small debug CLI can be added later, but the on-disk format should already be understandable.

## Testing plan

### 1. Model tests

Test:

- status validation
- patch validation
- attempt-record validation
- artifact and blocker model validation

### 2. Graph invariant tests

Test:

- cycle detection
- unknown dependency rejection
- self-dependency rejection
- readiness recomputation
- terminal-task claim rejection

### 3. Persistence tests

Test:

- creating an initial empty state
- round-tripping `state.json`
- appending and reloading events
- writing and reloading attempt records

### 4. Recovery tests

Test:

- interrupted `in_progress` task is requeued on restart
- stale attempt metadata does not corrupt the graph

### 5. Integration tests with the future runner

Once the agent runtime exists, test:

- initializer seeding tasks
- orchestrator selecting ready work
- worker attempt creation and completion
- orchestrator patch application after worker reports

## Suggested implementation phases

### Phase 1: models and persistence

- create `tasks/models.py`
- create `tasks/store.py`
- define file layout and revisioning
- add round-trip tests

### Phase 2: graph service

- create `tasks/service.py`
- implement create/patch/claim/finish operations
- implement DAG validation and readiness recomputation
- add invariant tests

### Phase 3: attempt tracking and recovery

- add `TaskAttempt` persistence
- implement interrupted-run recovery
- add recovery tests

### Phase 4: runner integration points

- expose snapshot/query helpers the orchestrator will need
- expose claim/finish hooks the runner will need
- document the typed patch surface for agent outputs

## Acceptance criteria

The task system is ready when all of the following are true:

- it persists a validated task graph on disk
- it prevents invalid dependency graphs
- it can answer which tasks are ready, blocked, in progress, and complete
- it records worker attempts separately from task definitions
- task attempts can reference detailed run telemetry and cost summaries
- it can recover cleanly after an interrupted run
- it exposes a typed mutation interface suitable for orchestrator outputs
- it is fully tested without requiring live model calls
