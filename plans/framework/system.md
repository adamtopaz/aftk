# Plan: agent system for the autoformalization framework

## Goal

Implement the framework component's initializer/orchestrator/worker runtime on top of:

- the persistent task system
- the existing toolkit client, `aftk_client.AsyncAftkClient`
- **pydantic-ai** as the model-facing agent framework

The agent system should be structured, typed, testable, and subordinate to deterministic Python control flow.
The runner owns state transitions; agents produce decisions and reports.

## Why pydantic-ai fits this framework

The pydantic-ai docs line up well with what we need.

We want:

- reusable `Agent` objects for each role
- typed dependency injection for runtime services
- structured output validation for decisions and reports
- explicit tool registration for toolkit and project operations
- good testing support through `TestModel`, `FunctionModel`, and agent overrides
- access to message history for logging and audit
- usage limits and model configuration for operational safety

The multi-agent docs also suggest a useful design choice for v1:

- prefer **programmatic hand-off** between agents in ordinary Python code
- do **not** start with graph-based orchestration machinery unless the flow becomes genuinely complex

That is a good fit here.
Our first loop is simple and hierarchical, so a plain async runner should come before any `pydantic-graph` integration.

## Pydantic AI implementation references

The most relevant docs for this plan are:

- [Agents](https://ai.pydantic.dev/agent/index.md) — agent construction, async `run()`, usage limits, and model/run settings
- [Dependencies](https://ai.pydantic.dev/dependencies/index.md) — typed deps, `RunContext`, and dependency overrides
- [Function Tools](https://ai.pydantic.dev/tools/index.md) — context-aware/plain tools and generated tool schemas
- [Toolsets](https://ai.pydantic.dev/toolsets/index.md) — reusable role-scoped tool collections and overrides
- [Output](https://ai.pydantic.dev/output/index.md) — structured output types and output modes
- [Messages and chat history](https://ai.pydantic.dev/message-history/index.md) — message capture, JSON persistence, and history reuse
- [Multi-Agent Patterns](https://ai.pydantic.dev/multi-agent-applications/index.md) — especially programmatic agent hand-off for the initializer/orchestrator/worker loop
- [Testing](https://ai.pydantic.dev/testing/index.md) — `TestModel`, `FunctionModel`, `Agent.override(...)`, and test isolation patterns
- [Model Providers](https://ai.pydantic.dev/models/overview/index.md) — provider-qualified model naming, fallback, and concurrency options
- [HTTP Request Retries](https://ai.pydantic.dev/retries/index.md) — provider HTTP retry transports if we need them
- [Pydantic Logfire / OpenTelemetry](https://ai.pydantic.dev/logfire/index.md) — optional supplemental instrumentation alongside the framework's own logs

## High-level runtime model

The runtime should look like this:

```text
project inputs
    ↓
project snapshot builder
    ↓
initializer agent (once)
    ↓
persistent task graph
    ↓
repeat:
  orchestrator agent
      ↓
  runner validates decision
      ↓
  worker agent executes one task
      ↓
  runner records report + telemetry + updates persistent state
```

The key boundary is:

- **agents think**
- **the runner commits state**

## Package structure

A reasonable Python package layout for the new framework code is:

```text
aftk/
  __init__.py
  config.py
  project.py
  runner.py
  storage/
    __init__.py
    paths.py
    runs.py
    telemetry.py
    costs.py
  tasks/
    models.py
    store.py
    service.py
  coding/
    __init__.py
    models.py
    filesystem.py
    search.py
    commands.py
  agents/
    __init__.py
    deps.py
    models.py
    initializer.py
    orchestrator.py
    worker.py
    tools/
      __init__.py
      toolkit.py
      project.py
      coding.py
```

Notes:

- `tasks/` is the non-LLM infrastructure described in `plans/framework/tasks.md`
- `coding/` should own deterministic filesystem, search, and command-execution services
- `storage/` should own per-run records, detailed telemetry logs, and cost ledgers
- `agents/models.py` should own typed outputs such as initializer results and worker reports
- `agents/tools/` should hold modular tool registration helpers
- `runner.py` should orchestrate the end-to-end loop and expose role-scoped toolsets

We will also need to update packaging so the repository installs the harmonized `aftk/` package, not just `aftk_client`.
The current `aftk_client/` package is an existing toolkit-facing Python surface and should either be re-exported from or migrated into `aftk/` as packaging is harmonized.
Separately, `.aftk/` is the generated runtime-state directory inside a project workspace.

## Core configuration model

Add a Pydantic configuration model, for example in `config.py`, with fields such as:

```text
FrameworkConfig
  project_root: Path
  entrypoint_path: Path
  sources_dir: Path
  state_dir: Path
  initializer_model: str
  orchestrator_model: str
  worker_model: str
  default_usage_limits: ...
  max_worker_retries: int
  allow_code_writes: bool
  allow_command_execution: bool
  command_timeout_seconds: float
  enable_detailed_logging: bool
  track_costs: bool
  pricing_overrides_path: Path | None
```

The exact shape can evolve, but we should keep per-agent model selection explicit from the start.
Pydantic AI supports different models per agent, which is useful here.

## Dependency injection design

The pydantic-ai docs strongly suggest using typed dependency containers.
We should do that.

Recommended dataclass-style deps objects:

### `InitializerDeps`

```text
InitializerDeps
  config: FrameworkConfig
  project_snapshot: ProjectSnapshot
  toolkit_client: AsyncAftkClient
```

### `OrchestratorDeps`

```text
OrchestratorDeps
  config: FrameworkConfig
  project_snapshot: ProjectSnapshot
  task_snapshot: TaskState
  toolkit_client: AsyncAftkClient
  last_worker_report: WorkerReport | None
```

### `WorkerDeps`

```text
WorkerDeps
  config: FrameworkConfig
  project_snapshot: ProjectSnapshot
  task_brief: WorkerTaskBrief
  toolkit_client: AsyncAftkClient
```

Important principle:

- the worker deps should not include the mutable task service
- the orchestrator may inspect task state, but actual writes still happen through the runner

These dependency sketches are intentionally minimal.
In the actual implementation, role-appropriate service handles may also be provided either through typed deps or through runner-constructed tool wrappers.
In particular, worker-facing coding tools and framework-wide telemetry logging will need access to deterministic services owned by the runner.

## Project snapshot builder

Before any agent runs, the framework should construct a typed snapshot of the current project.
That snapshot should be separate from the task graph.

A useful model shape is:

```text
ProjectSnapshot
  project_root: str
  entrypoint_text: str
  source_inventory: list[SourceFileRecord]
  lean_files: list[str]
  generated_state_dir: str
```

This is built deterministically by Python code and persisted under `.aftk/project/`.
The initializer and orchestrator should consume this snapshot rather than re-scanning the entire project through prompt text every time.

## Agent outputs

The most important design choice is to make agent outputs structured.

### Initializer output

```text
InitializationResult
  project_summary: str
  assumptions: list[str]
  risks: list[str]
  initial_tasks: list[TaskDraft]
```

This seeds the task system.

### Orchestrator output

```text
OrchestratorDecision
  project_done: bool
  selected_task_id: str | None
  new_tasks: list[TaskDraft]
  task_patches: list[TaskPatch]
  worker_brief: WorkerTaskBrief | None
  rationale: str
  completion_summary: str | None
```

This gives the runner a typed patch surface.
The runner must validate the decision before applying it.

### Worker output

```text
WorkerReport
  outcome: "completed" | "partial" | "blocked" | "failed"
  summary: str
  evidence: list[str]
  changed_artifacts: list[ArtifactRef]
  followup_tasks: list[TaskDraft]
  blockers: list[Blocker]
  handoff_notes: str | None
```

This is the worker-to-orchestrator handoff.
Follow-up tasks are only proposals; the runner does not insert them directly unless the orchestrator later approves them.

### Worker brief model

The worker should not receive the whole task graph.
Give it a focused brief:

```text
WorkerTaskBrief
  task_id: str
  title: str
  description: str
  acceptance_criteria: list[str]
  scope: list[ArtifactRef]
  local_context: str
  suggested_starting_points: list[str]
```

This keeps the worker local and reduces context bloat.

## Agent definitions

### Initializer agent

The initializer should be a pydantic-ai `Agent[InitializerDeps, InitializationResult]`.

Responsibilities:

- interpret `entrypoint.md`
- inspect source inventory
- inspect existing Lean project state
- summarize the starting point
- create the first task drafts

Tool access:

- project read tools
- toolkit query tools
- no task mutation tools

### Orchestrator agent

The orchestrator should be an `Agent[OrchestratorDeps, OrchestratorDecision]`.

Responsibilities:

- inspect current task graph
- decide whether the project is done
- choose ready work
- add or revise tasks
- interpret worker reports
- keep the global plan coherent

Tool access:

- read-only task query helpers if needed
- project read tools
- toolkit query tools
- no coding tools for filesystem mutation, project search, or command execution
- no direct persistent mutation tools

### Worker agent

The worker should be an `Agent[WorkerDeps, WorkerReport]`.

Responsibilities:

- execute one task
- inspect local project context
- use toolkit and local project tools
- report outcome in a structured way

Tool access:

- toolkit query tools
- worker-only coding tools for project search, file reads, code edits, and command execution
- no task-graph tools beyond the local brief

## Prompt strategy

Pydantic AI supports both static instructions and dynamic system prompt functions.
We should use both.

Recommended split:

- **static role instructions** live in code
  - what the initializer/orchestrator/worker is supposed to do
  - what boundaries it must respect
- **dynamic system prompt functions** add per-run context from typed deps
  - project summary
  - task snapshot summaries
  - current task brief
  - relevant configuration or safety limits
- **user prompt input** is the minimal run-specific action request
  - e.g. “Initialize this project” or “Work on task `task-0007`”

This should be cleaner and more testable than building giant prompt strings ad hoc.

## Tooling strategy

Tool exposure should be modular and explicit.
Per the pydantic-ai Function Tools docs, tool schemas are derived from Python signatures and docstrings, so the framework's tool wrappers should use clear names, good parameter descriptions, and small typed return models.

### `agents/tools/toolkit.py`

Wrap the existing `AsyncAftkClient` methods as tool functions.
These should provide convenient, typed access to:

- knowledge-base queries
- informal-layer queries
- Lean hover / goal / node / tactic operations

The framework should reuse the current Python client rather than talking to JSON-RPC directly.

### `agents/tools/project.py`

Provide high-level read-oriented project context such as:

- read `entrypoint.md`
- inspect source inventory
- summarize project structure for prompts

This module should stay focused on project summaries and non-mutating context.
Arbitrary project-directory search and file reads for code work belong in the worker-only coding tools.

### `agents/tools/coding.py`

Wrap deterministic coding services from `aftk/coding/` as worker-facing pydantic-ai tools.
This surface should support:

- searching through files in the project directory
- reading files and relevant slices
- writing or editing code inside the project directory
- running local validation commands such as `lake build`

These tools should be exposed to workers only.
The orchestrator should not receive them.

## Tool permissions by role

Recommended initial policy:

### Initializer

- project summary/read tools
- toolkit query tools
- no coding tools

### Orchestrator

- project summary/read tools
- read-only task summary access
- toolkit query tools
- no coding tools
- no file mutation or command execution

### Worker

- project read tools limited to local scope
- toolkit query tools
- coding tools for project search, code editing, and command execution
- no task mutation tools

This preserves the hierarchy from the top-level framework plan.

## Runner design

The runner should be a normal async Python service, not itself an LLM agent.

High-level flow:

1. load config
2. build project snapshot
3. open a shared `AsyncAftkClient` for the project root
4. construct role-scoped toolsets
   - initializer/orchestrator get read-only tool access
   - workers get coding tools in addition to toolkit query tools
5. if no task state exists, run the initializer and seed the task graph
6. loop:
   - load task snapshot
   - run orchestrator
   - persist orchestrator transcripts, detailed LLM/tool logs, usage data, and cost data
   - validate the decision
   - apply any new tasks or task patches
   - if `project_done`, verify no required work remains and stop
   - otherwise claim the selected ready task
   - run the worker
   - persist the worker report, transcript, detailed LLM-call logs, detailed tool-call logs, usage data, cost data, and executed coding-tool actions
   - continue

This should be fully async because the toolkit client is async and pydantic-ai agents naturally support async `run()`.

## Decision validation in the runner

The runner should reject invalid orchestrator decisions before mutating state.
Examples:

- selected task id does not exist
- selected task is not ready
- decision claims `project_done` while non-terminal required tasks remain
- a patch introduces a cycle or unknown dependency

This is a crucial safety boundary.
The model should not be trusted with direct persistent mutation.

## Observability, transcripts, tool logs, and cost tracking

Pydantic AI exposes message history and usage information on results.
We should use that, but it is not enough by itself.
The framework should also log individual LLM calls and individual tool calls in deterministic Python code.
The message-history docs give us two concrete implementation hooks to lean on here: `result.new_messages_json()` for raw per-run dumps, and `ModelMessagesTypeAdapter` if we later want typed transcript reloads instead of opaque blobs.
If we add Logfire or another OpenTelemetry backend, that should remain supplemental to the framework's own on-disk logs rather than replacing them.

For every initializer, orchestrator, and worker run, persist at least:

- structured output object
- `result.new_messages_json()` or equivalent message dump
- a run-level summary record
- individual LLM-call records for every model request/response step in the run
- individual tool-call records for every toolkit or coding tool invocation
- usage summary
- estimated cost summary
- model name
- timestamps
- for worker runs, coding-tool logs such as file edits and command executions

A practical per-run layout is:

```text
.aftk/
  runs/
    <run-id>/
      result.json
      messages.json
      llm-calls.jsonl
      tool-calls.jsonl
      usage.json
      cost.json
      coding-actions.jsonl
```

In addition to per-run records, the framework should maintain project-level rollups so an operator can inspect usage and estimated cost by at least:

- task attempt
- agent role
- model
- project

Important principles:

- message history is an **audit artifact**
- detailed LLM/tool logs are an **operational artifact**
- the task graph is the **canonical state**

Do not make the transcript or telemetry logs the source of truth for project progress.

## Usage limits, pricing, and retries

The docs highlight usage limits as a first-class safety mechanism.
We should use them.

Recommended policy:

- define default usage limits in config
- apply stricter limits to workers than to the initializer when appropriate
- keep retry counts explicit and low
- store retry counts in task attempts or run metadata
- estimate cost from per-call usage plus configured pricing data when direct cost is not provided by the model/provider

The Agents docs are the primary reference for `UsageLimits`.
If provider-side HTTP retries become necessary, prefer the documented retry transports from the HTTP Request Retries docs over ad hoc retry code hidden inside framework services.

If a run fails because of model or tool errors, the runner should:

- record the failure
- keep the task state consistent
- still persist any partial telemetry and usage/cost data captured before failure
- either requeue or mark the task as failed/blocked according to policy

## Model selection strategy

Different roles may need different models.
That should be configurable, not hard-coded deep in agent definitions.
Per the Model Providers docs, the simplest starting point is provider-qualified model strings in config (for example `<provider>:<model>`), only dropping down to explicit model/provider objects when we need custom provider configuration, concurrency limiting, fallback behavior, or custom retry transports.

Reasonable initial policy:

- initializer: capable but not necessarily the most expensive model
- orchestrator: strongest reasoning model available within budget
- worker: configurable; may be same as orchestrator or a cheaper model for simpler tasks

Because the pydantic-ai multi-agent docs allow multiple models across agents, this is a natural fit.

## Testing plan

### 1. Pure unit tests for agent output models

Test:

- `InitializationResult`
- `OrchestratorDecision`
- `WorkerReport`
- `WorkerTaskBrief`

### 2. Agent tests using pydantic-ai test utilities

Use:

- `TestModel` for broad smoke tests of tool wiring and structured outputs
- `FunctionModel` for scenario-specific orchestrator and worker behavior
- agent overrides where needed to swap model/deps/toolsets in tests

These tests should verify that the framework logic works without making real model calls.

### 3. Tool tests

Test:

- toolkit tool wrappers against stub or fixture clients
- project/coding tools against fixture repositories and temporary directories
- command execution logging and timeout behavior for commands such as `lake build`
- deterministic tool-call logging for both toolkit and coding tools

### 4. Logging and cost-tracking tests

Test:

- one agent run that triggers multiple model requests produces multiple LLM-call records
- tool loops produce one tool-call record per invocation
- usage rollups match the underlying per-call records
- estimated cost rollups are persisted at run and task-attempt granularity

### 5. Runner integration tests

Use a small fixture project and test:

- initialization path when no task state exists
- one full orchestrator → worker → orchestrator cycle
- blocked-task reporting and follow-up task creation
- successful project completion path

### 6. End-to-end tests with a real toolkit server fixture

Once the framework is stable enough, add a small end-to-end test using the actual `AsyncAftkClient` and fixture Lean files.
The model can still be mocked while the tools are real.

## Suggested implementation phases

These phases are for the agent-system slice of the framework.
They assume the broader task-system and project-snapshot direction from `plans/framework.md`, and they should stay aligned with the coding-tool and telemetry infrastructure described across the planning docs.

### Phase 1: package skeleton and config

- create the new Python package
- add config and project snapshot types
- update packaging so the new package is installed

### Phase 2: agent output models and deps

- add `agents/models.py`
- add `agents/deps.py`
- define initializer/orchestrator/worker output types

### Phase 3: coding services and tool wrappers

- add deterministic services under `aftk/coding/`
- add `agents/tools/toolkit.py`
- add `agents/tools/project.py`
- add `agents/tools/coding.py`
- test wrappers and coding services independently

### Phase 4: telemetry and cost infrastructure

- add storage helpers for run records, per-call telemetry, and cost summaries
- instrument all model requests and tool invocations
- implement run/task/model cost rollups
- test logging and cost calculations independently

### Phase 5: agent definitions

- implement initializer agent
- implement orchestrator agent
- implement worker agent
- keep prompts small, typed, and role-specific

### Phase 6: runner integration

- implement `runner.py`
- wire it to the task service
- persist run metadata, transcripts, detailed LLM/tool logs, and cost summaries
- add decision validation

### Phase 7: tests and fixtures

- add model tests
- add mocked-agent runner tests
- add fixture-project integration tests

## Relevant pydantic-ai docs by phase

- **Phase 1: package skeleton and config** — [Model Providers](https://ai.pydantic.dev/models/overview/index.md)
- **Phase 2: agent output models and deps** — [Dependencies](https://ai.pydantic.dev/dependencies/index.md) and [Output](https://ai.pydantic.dev/output/index.md)
- **Phase 3: coding services and tool wrappers** — [Function Tools](https://ai.pydantic.dev/tools/index.md) and [Toolsets](https://ai.pydantic.dev/toolsets/index.md)
- **Phase 4: telemetry and cost infrastructure** — [Messages and chat history](https://ai.pydantic.dev/message-history/index.md), [Agents](https://ai.pydantic.dev/agent/index.md) for usage limits/settings, and optionally [Pydantic Logfire / OpenTelemetry](https://ai.pydantic.dev/logfire/index.md)
- **Phase 5: agent definitions** — [Agents](https://ai.pydantic.dev/agent/index.md), [Dependencies](https://ai.pydantic.dev/dependencies/index.md), and [Output](https://ai.pydantic.dev/output/index.md)
- **Phase 6: runner integration** — [Multi-Agent Patterns](https://ai.pydantic.dev/multi-agent-applications/index.md) for programmatic hand-off, plus [Agents](https://ai.pydantic.dev/agent/index.md) and [Messages and chat history](https://ai.pydantic.dev/message-history/index.md)
- **Phase 7: tests and fixtures** — [Testing](https://ai.pydantic.dev/testing/index.md), plus [Toolsets](https://ai.pydantic.dev/toolsets/index.md) and [Dependencies](https://ai.pydantic.dev/dependencies/index.md) for overrides

## Acceptance criteria

The agent system is ready when all of the following are true:

- initializer, orchestrator, and worker agents are implemented with pydantic-ai
- each agent has typed deps and typed structured outputs
- the runner performs programmatic hand-off between agents in async Python code
- the runner validates agent decisions before mutating task state
- worker agents cannot directly mutate the task graph
- worker agents can use coding tools to search files, edit code, and run commands such as `lake build`
- the orchestrator does not receive coding tools
- all LLM calls and tool calls are logged persistently, not just final run transcripts
- usage and estimated cost are persisted and roll up correctly at least by run and task attempt
- run transcripts, usage metadata, and worker coding-tool logs are persisted for audit
- the framework can complete at least one small fixture project end-to-end with mocked or controlled models
