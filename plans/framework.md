# Plan: autoformalization framework

## Goal

Build the framework component of AFTK as a Python autoformalization layer on top of the existing toolkit layers.
The framework should take a user project, turn the work into explicit tasks, and drive progress through a small hierarchy of agents until the project is complete.

Two implementation pieces matter most:

1. a persistent **task system**
2. a hierarchical **agent runtime** built with **pydantic-ai**

The task system should land first.
The agent runtime should be built on top of it rather than inventing its own implicit notion of project state.

## Terminology

In these plans:

- **AFTK** refers to the overall project
- **toolkit** refers to the already implemented lower layers and interfaces, including the server and `aftk_client`
- **framework** refers to the new autoformalization component being planned here, implemented in the `aftk/` Python package

## Inputs provided by the user

The expected project shape is:

1. `sources/` containing any source material the user wants to provide
   - PDFs, Markdown, LaTeX, notes, or nothing at all
2. an initial Lean project
   - with or without dependencies
   - with or without pre-existing formalization
3. an `entrypoint.md` file describing the goals of the project
   - this is the main human-written project brief
   - it can refer to the source material and existing Lean code as needed

## Core architectural commitments

The framework should preserve these design choices.

- **Use pydantic-ai for all LLM-facing agents.**
  Agents should have typed dependencies, typed tools, and typed structured outputs.
- **Use the existing toolkit interfaces rather than duplicating lower-layer semantics.**
  In practice this means using `aftk_client.AsyncAftkClient` for knowledge-base, informal, and transient Lean interaction.
- **Keep project state explicit and persistent.**
  The task graph, run records, and summaries should live on disk rather than only in model message history.
- **Keep orchestration hierarchical.**
  The initializer sets things up once, the orchestrator maintains the global plan, and workers execute a single task at a time.
- **Let deterministic Python code own state mutation.**
  Agents should return structured proposals and reports; the application layer should validate and commit changes.

## Non-goals for v1

The first version should deliberately avoid a few things.

- distributed or multi-machine execution
- a large swarm of concurrently running workers
- using long chat histories as the canonical memory of the system
- giving worker agents direct write access to the task graph
- introducing graph-based orchestration machinery before a simple loop becomes insufficient

Pydantic AI does support more complex multi-agent and graph patterns, but for this project the first version should start with explicit Python control flow and only add graph machinery if the loop truly becomes more complex.

## User-facing workflow

From the user's point of view, the workflow should be:

1. create or choose a Lean project
2. add optional source material under `sources/`
3. write `entrypoint.md` explaining the project goals
4. run the autoformalization framework
5. let the framework initialize project state, create tasks, and iterate on them
6. inspect progress through task state, run logs, and generated artifacts

## Generated framework state

The framework should keep its own generated state in a dedicated directory inside the project root, for example:

```text
.aftk/
  project/
  tasks/
  runs/
```

The leading dot is intentional: `.aftk/` is generated runtime state inside a project, while `aftk/` is the Python package for the framework component.

At a high level:

- `project/` stores summaries and source inventory derived from the user inputs
- `tasks/` stores the task graph and task history
- `runs/` stores initializer/orchestrator/worker run records, LLM-call logs, tool-call logs, message logs, usage metadata, cost records, and worker coding-action logs

The exact file layout is described in:

- `plans/framework/tasks.md`
- `plans/framework/system.md`
- `plans/framework/coding_tools.md`

## Runtime components

The runtime has seven main pieces.

### 1. Project inputs

These are the user-authored inputs:

- `entrypoint.md`
- `sources/`
- the Lean project itself

### 2. Framework state

This is the persistent framework-owned state:

- project summaries
- task graph
- task attempts and outcomes
- run logs, model transcripts, tool-call logs, and cost ledgers

### 3. Toolkit runtime access

This is the bridge to the already implemented toolkit layers.
The framework should use the Python client and existing server surface for:

- knowledge-base operations
- informal-layer queries and presentation
- transient Lean interaction such as hover, goals, node loading, and tactic execution

### 4. Coding tools

This is the local project-editing surface exposed by the runner.
It should support:

- searching through files in the project directory
- reading local files and file slices
- writing or editing code within the project directory
- running validation commands such as `lake build`

These tools should be **worker-only**.
The orchestrator should not receive filesystem-mutation or command-execution tools.

### 5. Agents

The framework should begin with three agent roles.

- **Initializer** — runs once at the beginning
- **Orchestrator** — owns the global view of project progress
- **Worker** — executes one concrete task at a time

### 6. Runner / control loop

A deterministic Python runner should:

- build the project snapshot
- call the initializer if needed
- repeatedly call the orchestrator
- dispatch work to workers
- validate and persist every resulting state change
- capture and persist logs for LLM calls, tool calls, usage, and cost

### 7. Observability and cost tracking

The framework should treat observability as core infrastructure.
It should persist:

- task attempts and run outcomes
- individual LLM-call records
- individual tool-call records
- usage and cost summaries
- coding-action logs for worker-side file edits and command execution

Cost tracking should be aggregated at least by:

- run
- task attempt
- agent role
- model
- project

## Agent roles

### Initializer agent

The initializer is responsible for understanding the initial project state.
It should:

- inspect `entrypoint.md`
- inspect the available source material
- inspect the current Lean project state
- produce an initial project summary
- seed the first version of the task graph

It runs once during normal startup.
If we later support re-initialization, that should be an explicit operation rather than something that happens silently during ordinary runs.

### Orchestrator agent

The orchestrator owns the global plan.
It should:

- inspect the current task graph and project summary
- decide whether the project is finished
- choose which ready task should be worked on next
- create new tasks when new prerequisites or subproblems are discovered
- revise task statuses, dependencies, and priorities when appropriate
- interpret worker reports and decide how the graph should change afterward

The orchestrator should not do detailed task execution itself.
Its role is planning, routing, and global progress management.
It should not receive code-editing tools or command-execution tools such as `lake build`.

### Worker agent

A worker executes one task.
It should:

- receive a single task brief and relevant local context
- work only on that task
- use worker-only coding tools to search project files, edit code, and run validation commands such as `lake build` when needed
- make complete progress, partial progress, or determine that the task is blocked
- return a structured report explaining what happened
- explicitly describe missing prerequisites if the task cannot yet be completed

Workers should have a local view of the project, not a global planning role.
In particular, they should not own the task graph.

## Main loop

The core loop should look like this:

1. load the current project and task state
2. if no framework state exists yet, run the initializer and seed the task graph
3. ask the orchestrator for the next decision
4. if the orchestrator says the project is complete, validate that claim against the task state and stop
5. otherwise, claim the selected ready task
6. run a worker on that task
7. persist the worker report, any produced artifacts, and the associated LLM/tool/usage/cost logs
8. hand the updated state back to the orchestrator for the next iteration

The important boundary is that **the runner applies state changes**.
Agents do not directly mutate persistent state on their own.

## Observability, logging, and cost tracking

Task attempts alone are not enough for debugging or operations.
The framework should log the full execution surface.

At minimum, it should persist:

- run-level records for initializer, orchestrator, and worker runs
- individual LLM calls within those runs, not just the final transcript
- individual tool calls, including toolkit tools and coding tools
- coding actions such as file edits and command executions
- usage summaries and estimated cost summaries
- project-level rollups so an operator can understand where time and money are going

For LLM calls, the logs should preserve enough information to reconstruct what happened operationally, including:

- agent role
- run id
- model name
- timestamps and duration
- usage metadata
- message or request/response references
- estimated cost when available

For tool calls, the logs should preserve enough information to understand side effects and failures, including:

- tool name
- agent role
- timestamps and duration
- summarized inputs
- summarized outputs or errors
- task/run association

Cost tracking should not rely only on final run totals.
If a single agent run performs multiple model requests because of tool loops, those individual requests should still be logged and costed.

The observability layer is an audit surface, not the canonical source of project state.
The task graph remains canonical.

## Task-system principles

The task system should make the project state legible and restartable.

Core requirements:

- tasks are explicit, persistent objects
- tasks are small enough for a worker to execute with local context
- tasks live in a dependency DAG
- statuses are explicit
- blockers are explicit
- attempts and outcomes are recorded
- the graph can be reloaded after process restarts

The task system is not just bookkeeping.
It is the control surface that makes hierarchical orchestration possible.

## Why pydantic-ai is the right fit

The pydantic-ai docs map well onto this design.

For this framework we should use:

- **typed `Agent` definitions** for initializer, orchestrator, and worker roles
- **typed dependencies** to inject services like the toolkit client, project paths, and task services
- **function tools / toolsets** to expose toolkit and project operations to agents in a controlled way
- **role-scoped toolsets** so worker agents can get coding tools while the orchestrator remains read-only with respect to the project workspace
- **structured output types** so decisions and worker reports are validated before we apply them
- **message history access** for audit logs and debugging
- **usage limits and model configuration** for safety and reproducibility
- **test utilities** such as `TestModel`, `FunctionModel`, and agent overrides for unit and integration tests

The multi-agent docs also make an important design point: not every multi-agent system needs graph machinery.
For v1, the best fit is **programmatic hand-off in ordinary Python control flow**.
If the runner later needs richer branching, joins, or parallel execution, we can revisit `pydantic-graph`.

## Pydantic AI documentation map

While implementing the framework, keep these docs open:

- [Agents](https://ai.pydantic.dev/agent/index.md) — agent lifecycle, async runs, usage limits, and run/model settings
- [Dependencies](https://ai.pydantic.dev/dependencies/index.md) — typed deps via `RunContext`
- [Function Tools](https://ai.pydantic.dev/tools/index.md) — `@agent.tool`, `@agent.tool_plain`, tool schemas, and docstring-derived parameter descriptions
- [Toolsets](https://ai.pydantic.dev/toolsets/index.md) — reusable, composable, role-scoped tool collections
- [Output](https://ai.pydantic.dev/output/index.md) — structured output types for initializer/orchestrator/worker results
- [Messages and chat history](https://ai.pydantic.dev/message-history/index.md) — `new_messages_json()`, JSON persistence, and history reuse
- [Multi-Agent Patterns](https://ai.pydantic.dev/multi-agent-applications/index.md) — especially programmatic agent hand-off for v1
- [Testing](https://ai.pydantic.dev/testing/index.md) — `TestModel`, `FunctionModel`, `Agent.override(...)`, and test-only tool/model swaps
- [Model Providers](https://ai.pydantic.dev/models/overview/index.md) — provider-qualified model names, fallback, and concurrency options
- [HTTP Request Retries](https://ai.pydantic.dev/retries/index.md) — provider HTTP retry transports if we need them
- [Pydantic Logfire / OpenTelemetry](https://ai.pydantic.dev/logfire/index.md) — optional supplemental instrumentation, not canonical project state

## Implementation order

The practical order should be:

1. implement the task system in Python
2. implement project-state discovery and persistence helpers
3. implement worker-facing coding tools for project search, code editing, and commands such as `lake build`
4. implement observability and cost-tracking infrastructure
5. implement the initializer agent
6. implement the orchestrator and worker agents
7. implement the runner loop that ties them together
8. add tests and fixture projects
9. add operator-facing inspection tools and cost/reporting views

## Phased implementation plan

A practical phased plan for the framework is:

### Phase 1: package and repository setup

Scope:

- establish the harmonized `aftk/` Python package layout
- update packaging so the new package is installed cleanly
- keep the existing toolkit-facing `aftk_client` surface available during the transition
- add basic module skeletons for config, project state, tasks, coding, agents, and runner

Exit criteria:

- `aftk/` exists as the main Python package root
- packaging discovers the intended packages
- imports are stable enough to begin implementing subsystems underneath them

### Phase 2: task system

Scope:

- implement the Pydantic task models
- implement task persistence under `.aftk/tasks/`
- implement graph validation, readiness computation, claiming, attempts, and recovery
- add unit tests for task invariants and persistence

Exit criteria:

- the framework can persist and reload a valid task graph
- ready, blocked, in-progress, and completed tasks can be computed reliably
- interrupted runs can be recovered without corrupting state

### Phase 3: project snapshot and framework state

Scope:

- implement deterministic project scanning
- build and persist the project snapshot under `.aftk/project/`
- define the shared config and path models used by the runner and agents
- ensure the framework can discover `entrypoint.md`, `sources/`, and Lean project context consistently

Exit criteria:

- the framework can construct a typed project snapshot for a real project
- snapshot state is persisted and reusable across runs

### Phase 4: worker coding tools

Scope:

- implement deterministic coding services under `aftk/coding/`
- implement project-root sandboxing for reads, writes, search, and commands
- implement worker-facing pydantic-ai tool wrappers for search, file reads, edits, and commands such as `lake build`
- add logging for coding actions under `.aftk/runs/`

Exit criteria:

- worker coding tools can search files, edit code, and run `lake build`
- writes outside the project root and writes into `.aftk/` are rejected
- coding actions are auditable

### Phase 5: observability and cost-tracking infrastructure

Scope:

- define run-log models for agent runs, individual LLM calls, and individual tool calls
- persist detailed run logs under `.aftk/runs/`
- implement usage rollups and cost rollups by run, task attempt, agent role, model, and project
- add configurable cost estimation based on model usage and a pricing table or override mechanism

Exit criteria:

- the framework can persist individual LLM-call and tool-call records
- usage and estimated cost can be rolled up at least by run and task attempt
- operators can inspect where tokens, time, and money are being spent

### Phase 6: agent models, deps, and toolsets

Scope:

- implement typed dependency containers for initializer, orchestrator, and worker runs
- implement structured output models such as `InitializationResult`, `OrchestratorDecision`, and `WorkerReport`
- wire role-scoped toolsets so the orchestrator remains read-only while workers receive coding tools
- add unit tests using pydantic-ai test utilities where possible

Exit criteria:

- agent inputs and outputs are fully typed
- tool access is correctly restricted by role
- the runner can construct the correct dependencies and toolsets for each role

### Phase 7: initializer agent

Scope:

- implement the initializer agent
- make it consume the project snapshot and toolkit tools
- make it produce an initial project summary and a first set of task drafts
- integrate initializer output with the task system

Exit criteria:

- a fresh project can be initialized into persistent framework state
- the task graph can be seeded from the initializer output

### Phase 8: orchestrator, worker, and runner loop

Scope:

- implement the orchestrator agent
- implement the worker agent
- implement the async runner loop that validates decisions and applies state changes
- persist transcripts, LLM-call logs, tool-call logs, usage metadata, cost records, worker reports, and coding-action logs
- ensure the orchestrator never receives code-editing or command-execution tools

Exit criteria:

- the framework can run an end-to-end orchestrator → worker → orchestrator cycle
- task claims, worker execution, and post-run updates are all persisted correctly
- the planner/executor boundary is enforced by code, not just prompts
- detailed observability survives process restarts and can be inspected after the fact

### Phase 9: fixture projects, integration tests, and operator visibility

Scope:

- add fixture projects for initialization and edit/build workflows
- add integration tests for task flow, worker edits, `lake build`, and logging/cost rollups
- add end-to-end tests with mocked or controlled models and real toolkit interactions where appropriate
- improve inspection of `.aftk/` state, run logs, and cost summaries

Exit criteria:

- at least one small fixture project runs end-to-end successfully
- the framework is auditable enough for debugging and iteration
- cost and usage data are visible enough to guide operational choices
- the implementation is stable enough to start refining prompts and task decomposition quality

## Relevant pydantic-ai docs by implementation phase

- **Phase 1 / cross-cutting model configuration** — [Model Providers](https://ai.pydantic.dev/models/overview/index.md) and, if provider-side retry behavior becomes important, [HTTP Request Retries](https://ai.pydantic.dev/retries/index.md)
- **Phase 4: worker coding tools** — [Function Tools](https://ai.pydantic.dev/tools/index.md) and [Toolsets](https://ai.pydantic.dev/toolsets/index.md)
- **Phase 5: observability and cost tracking** — [Messages and chat history](https://ai.pydantic.dev/message-history/index.md), [Agents](https://ai.pydantic.dev/agent/index.md) for usage limits/settings, and optionally [Pydantic Logfire / OpenTelemetry](https://ai.pydantic.dev/logfire/index.md)
- **Phase 6: agent models, deps, and toolsets** — [Agents](https://ai.pydantic.dev/agent/index.md), [Dependencies](https://ai.pydantic.dev/dependencies/index.md), [Output](https://ai.pydantic.dev/output/index.md), and [Toolsets](https://ai.pydantic.dev/toolsets/index.md)
- **Phase 7: initializer agent** — [Agents](https://ai.pydantic.dev/agent/index.md), [Dependencies](https://ai.pydantic.dev/dependencies/index.md), and [Output](https://ai.pydantic.dev/output/index.md)
- **Phase 8: orchestrator, worker, and runner loop** — [Multi-Agent Patterns](https://ai.pydantic.dev/multi-agent-applications/index.md) for programmatic hand-off, plus [Agents](https://ai.pydantic.dev/agent/index.md) and [Messages and chat history](https://ai.pydantic.dev/message-history/index.md)
- **Phase 9: tests and fixtures** — [Testing](https://ai.pydantic.dev/testing/index.md)

## Detailed subplans

- `plans/framework/tasks.md` — implementation plan for the task system
- `plans/framework/system.md` — implementation plan for the pydantic-ai agent system, runner integration, telemetry, and cost tracking
- `plans/framework/coding_tools.md` — implementation plan for worker-only coding and command tools

## Acceptance criteria for the overall framework

This framework plan is realized when all of the following are true:

- a project can be initialized from `entrypoint.md`, `sources/`, and the Lean workspace
- task state is persisted and restartable
- the orchestrator can choose ready work from an explicit DAG of atomic tasks
- workers execute one task at a time and return structured reports
- worker agents can search project files, edit code, and run validation commands such as `lake build`
- the orchestrator does not receive code-editing or command-execution tools
- all LLM calls and tool calls are logged persistently, not just task attempts
- usage and estimated cost are tracked at least by run, task attempt, agent role, and model
- the system uses pydantic-ai for model interaction
- the framework uses existing toolkit interfaces rather than duplicating them
- the whole loop can run end-to-end on at least one small fixture project
