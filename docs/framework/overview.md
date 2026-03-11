# Framework overview

The experimental framework layer is the Python orchestration layer under `aftk/`.
It sits on top of the Lean/toolkit layers and adds:

- deterministic project snapshots
- a persistent task graph under `.aftk/tasks/`
- `pydantic-ai` initializer, orchestrator, and worker agents
- worker-only coding tools for local edits and validation commands
- per-run telemetry, usage summaries, cost rollups, and inspection reports

Today this layer exposes an **experimental Hydra-backed CLI** as `autoformalize` as well as the underlying library APIs.
It is still early and not yet a polished stable end-user product.
You can run it through `autoformalize` and inspect the resulting state with `aftk-inspect`.

For the implementation map, see `docs/framework/library.md`.
For the design documents that shaped the current implementation, see `plans/framework.md` and `plans/framework/*.md`.

## What a project needs

The framework expects a normal Lake project root plus a small amount of project-specific input:

- `lakefile.lean` or `lakefile.toml`
- `entrypoint.md`
- optional `sources/`
- any Lean files already present in the project

A minimal project can look like this:

```text
my-project/
  lakefile.toml
  entrypoint.md
  Demo.lean
  sources/           # optional
    notes.md
    paper.pdf
```

Recommended meanings:

- `entrypoint.md` is the human-written project brief
- `sources/` contains optional external material such as notes, PDFs, or Markdown
- Lean files are the workspace the worker agent can inspect and edit

## Minimal end-to-end run

### 1. Install Python dependencies

From the repository root:

```text
uv sync
```

If you also need the Lean binaries built locally, run:

```text
lake build
```

### 2. Choose models and set provider credentials

The framework uses `pydantic-ai`, so you should configure whatever environment variables your chosen provider requires.
Model names follow Pydantic AI's `provider:model` format, for example:

- `openai:gpt-5-mini`
- `openrouter:google/gemini-2.5-pro`
- `anthropic:claude-sonnet-4-5`

### 3. Run the framework through the Hydra CLI

From the project root, run `autoformalize` with Hydra overrides for the three agent models:

```text
uv run autoformalize \
  project_root=. \
  models.initializer='openai:gpt-5-mini' \
  models.orchestrator='openai:gpt-5' \
  models.worker='openai:gpt-5-mini'
```

Useful optional overrides:

```text
uv run autoformalize \
  project_root=. \
  max_iterations=20 \
  state_dir=.aftk \
  output=text \
  models.initializer='openai:gpt-5-mini' \
  models.orchestrator='openai:gpt-5' \
  models.worker='openai:gpt-5-mini'
```

The CLI uses Hydra for config management and reads defaults from the packaged `aftk/conf/main.yaml`.
By default, the underlying `FrameworkRunner` creates its own `AsyncAftkClient`, which in turn starts `lake exe aftk_server` for the project automatically.
For the basic workflow you do **not** need to start the server manually.

If `aftk` is installed as a Lake dependency in another project, you can also launch the framework from that project's root with:

```text
lake run autoformalize \
  models.initializer='openai:gpt-5-mini' \
  models.orchestrator='openai:gpt-5' \
  models.worker='openai:gpt-5-mini'
```

That Lake script resolves the Python environment from the `aftk` dependency package while forcing the command's working directory to be the root of the current Lean/Lake project.
This matches the framework's assumption that the current working directory is always the project root being formalized.

### 4. Inspect the persisted state

After the run creates `.aftk/`, inspect it with:

```text
uv run aftk-inspect .
```

For JSON output:

```text
uv run aftk-inspect . --json
```

Useful report-shaping flags:

```text
uv run aftk-inspect . --max-events 5 --max-run-lines 5
uv run aftk-inspect . --rebuild-rollups
```

## What the runner does

A normal `FrameworkRunner.run()` call performs this loop:

1. validate and load the project configuration
2. recover interrupted `in_progress` tasks back to a schedulable state
3. build and persist `.aftk/project/snapshot.json`
4. run the initializer once if the project has not been initialized yet
5. repeatedly run the orchestrator
6. validate any proposed graph changes before applying them
7. claim one ready task and run a worker on it
8. persist worker results, task attempts, transcripts, tool logs, and rollups
9. stop when the orchestrator proposes a valid `project_done` decision

If `.aftk/` already exists, rerunning the same driver resumes from the persisted project/task/run state instead of starting from scratch.

## What lands under `.aftk/`

The current on-disk layout is:

```text
.aftk/
  project/
    snapshot.json
    initialization.json
  tasks/
    state.json
    events.jsonl
    attempts/
      attempt-0001.json
  runs/
    run-0001/
      run.json
      result.json
      messages.json
      llm-calls.jsonl
      tool-calls.jsonl
      usage.json
      cost.json
      coding-actions.jsonl
    project-rollups.json
```

The important split is:

- `project/` — deterministic project snapshot and initialization record
- `tasks/` — canonical task graph plus task events and immutable attempts
- `runs/` — operational telemetry for initializer/orchestrator/worker runs

## Role boundaries and tool permissions

The framework enforces a strict planner/executor split.

### Initializer

Gets:

- project snapshot tools
- toolkit query tools

Does not get:

- local coding tools
- task-state mutation tools

### Orchestrator

Gets:

- project snapshot tools
- toolkit query tools
- the persisted task snapshot through structured deps

Does not get:

- local coding tools
- filesystem mutation or command execution
- direct task-state mutation

### Worker

Gets:

- project snapshot tools
- toolkit query tools
- coding tools for file search, reads, edits, and commands such as `lake build`

Does not get:

- direct task-graph mutation
- permission to write outside the project root
- permission to edit `.aftk/`

The worker reports what happened; the runner and task service decide how persistent state changes.

## Programmatic entrypoints

The most useful public Python surfaces are:

- `aftk.config.FrameworkConfig`
  - validates framework paths
  - stores per-role model names
- `aftk.project.ProjectSnapshotService`
  - builds and persists deterministic project snapshots
- `aftk.tasks.TaskService`
  - owns task creation, patching, claiming, attempts, and recovery
- `aftk.runner.FrameworkRunner`
  - runs the full initializer → orchestrator → worker loop
- `aftk.inspection.FrameworkInspectionService`
  - builds text or JSON inspection reports over `.aftk/`
- `aftk.agents.InitializerService`, `OrchestratorService`, `WorkerService`
  - lower-level role-specific services if you want to drive roles individually

## Optional advanced usage

### Pass explicit models at run time

Instead of storing model names in `FrameworkConfig`, you can pass them directly to the runner:

```python
result = await runner.run(
    initializer_model="openai:gpt-5-mini",
    orchestrator_model="openai:gpt-5",
    worker_model="openai:gpt-5-mini",
)
```

### Reuse a shared toolkit client

If you want tighter control over the toolkit connection, create the client yourself:

```python
import asyncio

from aftk.config import FrameworkConfig
from aftk.runner import FrameworkRunner
from aftk_client import AsyncAftkClient


async def main() -> None:
    config = FrameworkConfig.from_project_root(".")
    runner = FrameworkRunner(config)
    async with AsyncAftkClient(project_root=config.project_root) as client:
        await runner.run(
            toolkit_client=client,
            initializer_model="openai:gpt-5-mini",
            orchestrator_model="openai:gpt-5",
            worker_model="openai:gpt-5-mini",
        )


asyncio.run(main())
```

### Add pricing rules for cost rollups

If you want estimated costs in rollups, pass a pricing table to the runner:

```python
from aftk.runner import FrameworkRunner
from aftk.storage import PricingTable

pricing = PricingTable.from_json_file("pricing-overrides.json")
runner = FrameworkRunner(config, pricing_table=pricing)
```

## Current limitations

Important current boundaries:

- the runner is library-first; there is no stable top-level runner CLI yet
- execution is single-process and sequential
- the task graph is the canonical control state; workers do not mutate it directly
- coding tools are intentionally sandboxed to the project root and cannot edit `.aftk/`
- inspection is currently text/JSON oriented rather than a full interactive UI

That said, the framework is already usable for controlled end-to-end runs, fixture projects, and iterative development on top of the lower AFTK layers.
