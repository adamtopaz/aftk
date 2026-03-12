# Framework library guide

This guide maps the implemented Python framework surface to the main modules you will import in real code.
It is the best companion to `docs/framework/overview.md` when you want to go beyond the minimal quickstart.
The experimental CLI wrapper is exposed as `autoformalize` and is implemented in `aftk.cli`, with the repository-root `main.py` kept as a thin compatibility shim.
When `aftk` is used as a Lake dependency, the package also exposes a `lake run autoformalize -- ...` script that forwards to the same Python CLI while preserving the dependent project's root as the working directory.

## Mental model

The framework is split into a few clean layers inside `aftk/`:

```text
config + project snapshot
        ↓
task graph
        ↓
coding services + tool wrappers
        ↓
initializer / orchestrator / worker agents
        ↓
runner loop
        ↓
inspection + rollups
```

The two most important boundaries are:

- deterministic Python code owns persistent state
- agents return structured outputs, not arbitrary state mutations

## `aftk.config`

Primary types:

- `FrameworkConfig`
- `FrameworkPaths`
- `AgentModelSettings`

Use this module when you need to:

- validate that a project root is a Lake project
- locate `entrypoint.md`, `sources/`, and `.aftk/`
- store per-role model names in `provider:model` format

Typical usage:

```python
from aftk.config import AgentModelSettings, FrameworkConfig

config = FrameworkConfig.from_project_root(
    ".",
    models=AgentModelSettings(
        initializer="openai:gpt-5-mini",
        orchestrator="openai:gpt-5",
        worker="openai:gpt-5-mini",
    ),
)
```

## `aftk.project`

Primary types:

- `ProjectSnapshot`
- `ProjectSnapshotService`
- `ProjectSnapshotStore`
- `SourceFileRecord`
- `LeanFileRecord`

Use this module when you need a deterministic view of project inputs before any agent runs.
The snapshot includes:

- project root
- entrypoint path and text
- source inventory with hashes
- discovered Lean files with hashes
- generated state directory
- detected `lakefile.lean` or `lakefile.toml`

Typical usage:

```python
from aftk.project import ProjectSnapshotService

snapshot_service = ProjectSnapshotService(config)
snapshot = snapshot_service.build_and_save_snapshot()
```

## `aftk.tasks`

Primary types:

- models: `Task`, `TaskDraft`, `TaskPatch`, `TaskAttempt`, `TaskState`
- enums/value types: `TaskStatus`, `TaskPriority`, `ArtifactRef`, `Blocker`
- services: `TaskStore`, `TaskService`

This is the canonical control-state layer.
If you want to understand or manipulate the task graph, start here.

Key `TaskService` operations:

- `load_state()`
- `list_ready_tasks()`
- `create_tasks(...)`
- `apply_patch(...)` / `apply_patches(...)`
- `claim_task(...)`
- `finish_attempt(...)`
- `recover_interrupted_tasks(...)`
- `topological_order(...)`

Typical usage:

```python
from aftk.tasks import TaskDraft, TaskService

service = TaskService(config.paths.tasks_dir)
created = service.create_tasks(
    [
        TaskDraft(
            title="Inspect Demo.lean",
            description="Identify the first unfinished proof.",
            kind="formalization",
            acceptance_criteria=["The first unfinished goal is identified."],
        )
    ],
    actor="initializer",
)
```

Important design rule:

- attempts are recorded separately from task definitions
- `finish_attempt(...)` records the immutable attempt outcome and artifacts
- `reconcile_finished_attempt(...)` deterministically folds that terminal attempt back into task state
- interrupted `in_progress` tasks are recovered and validated on startup before the runner continues

## `aftk.coding`

Primary services:

- `ProjectSearchService`
- `ProjectFileService`
- `ProjectCommandService`
- `CodingActionRecorder`

Primary result models:

- `ProjectPath`
- `SearchMatch`
- `FileReadResult`
- `FileWriteResult`
- `FileEditResult`
- `CommandResult`
- `CodingAction`

This is the deterministic side-effect layer used by worker tools.
It provides:

- sandboxed project search
- UTF-8 file reads and slices
- atomic writes and exact-text replacement
- project-root command execution
- coding-action audit logs

Typical usage:

```python
from aftk.coding import ProjectFileService

files = ProjectFileService(config)
result = files.replace_in_file(
    "Demo.lean",
    "theorem demo : True := by\n  sorry\n",
    "theorem demo : True := by\n  trivial\n",
)
```

Important safeguards:

- paths may not escape the project root
- symlink escapes are rejected
- writes into `.aftk/` are rejected
- command executions are logged

## `aftk.logging`

Primary types/functions:

- `LoggingCliConfig`
- `LoggingRuntime`
- `setup_logging(...)`
- `log_event(...)`

This module owns the framework's operator-facing logging policy.
It configures:

- console logging for live progress
- `.aftk/cli.log` for persistent session logs
- `.aftk/events.jsonl` for structured runtime events
- dependency logger suppression by default
- live `pydantic-ai` event streaming for tool calls, retries, and final-result traces

Typical usage:

```python
from aftk.logging import LoggingCliConfig, setup_logging

runtime = setup_logging(LoggingCliConfig(level="debug"), config)
try:
    ...
finally:
    runtime.close()
```

## `aftk.agents`

Primary types:

- deps: `InitializerDeps`, `OrchestratorDeps`, `WorkerDeps`
- structured outputs: `InitializationResult`, `OrchestratorDecision`, `WorkerReport`, `WorkerTaskBrief`
- services: `InitializerService`, `OrchestratorService`, `WorkerService`
- builders: `build_initializer_agent`, `build_orchestrator_agent`, `build_worker_agent`
- tool builders: `build_initializer_toolsets`, `build_orchestrator_toolsets`, `build_worker_toolsets`

This module is where the `pydantic-ai` integration lives.
It gives each role:

- typed deps
- structured output validation
- role-scoped tools
- role-specific instructions

Typical usage for a worker brief:

```python
from aftk.agents import WorkerTaskBrief

brief = WorkerTaskBrief.from_task(task, local_context="Focus on Demo.lean lines 1-20")
```

Typical usage for direct role execution:

```python
from aftk.agents import WorkerService

worker = WorkerService(config)
result = await worker.run_worker(
    toolkit_client,
    task_brief=brief,
    model="openai:gpt-5-mini",
)
report = result.output
```

### Tool modules

The role-scoped tool wrappers live under `aftk.agents.tools`:

- `project.py` — snapshot-backed read-only project tools
- `toolkit.py` — `AsyncAftkClient` wrappers for Lean/knowledge-base/informal operations, including Lean file-session tools such as `open` and `close`
- `coding.py` — worker-only coding tools backed by `aftk.coding`

Policy summary:

- initializer: project + toolkit tools
- orchestrator: project + toolkit tools
- worker: project + toolkit + coding tools

The toolkit toolset exposes explicit Lean file-session lifecycle operations (`open`, `close`) alongside file-scoped Lean queries. Model-facing toolsets also convert common recoverable tool failures into retry prompts so the agent loop can continue instead of aborting immediately.

## `aftk.storage`

Primary types:

- run records: `AgentRunRecord`, `RunStatus`, `RunArtifacts`
- telemetry: `LlmCallRecord`, `ToolCallRecord`, `UsageSummary`, `ToolFamily`
- cost utilities: `PricingTable`, `CostSummary`, `estimate_usage_cost`
- rollups: `RunCollection`, `RunLogStore`, `RunTelemetrySession`, `ProjectRollupService`, `ProjectRollups`

Use this module when you need to:

- persist per-run telemetry
- write or inspect run artifacts
- estimate or aggregate token costs
- rebuild project rollups from `.aftk/runs/`

Typical usage:

```python
from aftk.storage import PricingTable, RunCollection

collection = RunCollection(config)
run_id = collection.next_run_id()
store = collection.run_store(run_id)
```

Most application code will not manipulate these pieces directly because `FrameworkRunner` already does it.
They are still useful for tooling, testing, and custom operators.

## `aftk.runner`

Primary types:

- `FrameworkRunner`
- `RunnerLoopResult`
- `RunnerDecisionError`
- `RunnerIterationLimitError`

This is the high-level entrypoint for the implemented framework.
It ties together:

- project snapshotting
- one-time initialization
- orchestrator decisions
- worker execution
- task claiming and attempts
- transcripts, LLM/tool telemetry, and rollups

Typical usage:

```python
from aftk.runner import FrameworkRunner

runner = FrameworkRunner(config)
result = await runner.run(max_iterations=20)
```

If you want the full framework behavior, this is the main API to call.

## `aftk.inspection`

Primary types:

- `FrameworkInspectionService`
- `FrameworkInspectionReport`
- `RunInspection`
- `TaskStatusCounts`
- `TaskEventCounts`

Use this module when you want programmatic inspection rather than the CLI.
It can:

- load snapshot, initialization, task, attempt, and run state
- summarize task counts and recent events
- summarize recent runs and coding-action counts
- emit text or JSON reports
- rebuild missing rollups from per-run logs

Typical usage:

```python
from aftk.inspection import FrameworkInspectionService

inspector = FrameworkInspectionService(config)
text_report = inspector.render_text_report()
json_report = inspector.render_json_report()
```

The CLI `aftk-inspect` is a thin wrapper around this service.

## Common usage patterns

### Run the whole framework

Use:

- `FrameworkConfig.from_project_root(...)`
- `FrameworkRunner(config)`
- `await runner.run(...)`

### Build snapshot state without running agents

Use:

- `ProjectSnapshotService(config).build_and_save_snapshot()`

### Seed or manipulate tasks manually

Use:

- `TaskService(config.paths.tasks_dir)`

This is useful in tests, prototypes, or operator tooling.

### Run a single role with controlled models

Use:

- `InitializerService`, `OrchestratorService`, or `WorkerService`
- `pydantic_ai.models.test.TestModel`
- `pydantic_ai.models.function.FunctionModel`

The framework tests under `tests/python/` are good examples of this style.

### Inspect or rebuild telemetry rollups

Use:

- `FrameworkInspectionService`
- `ProjectRollupService`

## Good example tests to read

If you want working examples of the framework API, these tests are especially useful:

- `tests/python/test_framework_project.py` — config and project snapshots
- `tests/python/test_framework_tasks.py` — task graph and attempts
- `tests/python/test_framework_coding.py` — filesystem/search/command tools
- `tests/python/test_framework_initializer.py` — initialization flow
- `tests/python/test_framework_agents.py` — role-scoped tools and typed outputs
- `tests/python/test_framework_runner.py` — end-to-end runner loop
- `tests/python/test_framework_visibility.py` — inspection and CLI reporting

## Practical recommendation

If you are new to the framework, use the modules in this order:

1. `aftk.config`
2. `aftk.project`
3. `aftk.runner`
4. `aftk.inspection`
5. `aftk.tasks` and `aftk.storage` only when you need lower-level control

That matches the current design: use the runner and inspection services for normal operation, and drop to the lower-level modules when building custom tooling or tests.
