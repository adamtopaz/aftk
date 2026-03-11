from __future__ import annotations

from typing import Any, Sequence

from pydantic_ai import Agent, RunContext
from pydantic_ai.agent import AgentRunResult
from pydantic_ai.toolsets import CombinedToolset

from aftk.agents.deps import WorkerDeps
from aftk.agents.models import WorkerReport
from aftk.agents.tools import build_worker_toolsets
from aftk.coding.logs import CodingActionRecorder
from aftk.config import FrameworkConfig, FrameworkPaths
from aftk.project import ProjectSnapshot, ProjectSnapshotService
from aftk.tasks import TaskService
from aftk_client import AsyncAftkClient


DEFAULT_WORKER_USER_PROMPT = (
    "Work on the assigned task using the provided local tools as needed. Return a WorkerReport describing the outcome, "
    "evidence, changed artifacts, blockers, and any follow-up tasks you think the orchestrator should consider."
)
_WORKER_ROLE_INSTRUCTIONS = """
You are a worker agent for the AFTK autoformalization framework.

Your job is to execute exactly one assigned task.

Requirements:
- stay local to the provided task brief and do not take on global planning responsibilities
- use the provided toolkit and coding tools when they help you inspect, edit, or validate the local project state
- do not mutate the task graph or claim completion by side effect; only report what happened
- use surgical edits when possible and validate your changes when appropriate
- if you are blocked, explain the missing prerequisite explicitly and include blockers in the WorkerReport
- follow-up tasks are proposals for the orchestrator, not direct mutations
""".strip()


def build_worker_agent(
    model: Any | None = None,
    *,
    toolsets: Sequence[Any] | None = None,
) -> Agent[WorkerDeps, WorkerReport]:
    configured_toolsets = [_default_worker_toolset] if toolsets is None else list(toolsets)
    agent = Agent(
        model,
        name="aftk_worker",
        deps_type=WorkerDeps,
        output_type=WorkerReport,
        instructions=_WORKER_ROLE_INSTRUCTIONS,
        toolsets=configured_toolsets,
        defer_model_check=model is None,
    )

    @agent.instructions
    def add_worker_context(ctx: RunContext[WorkerDeps]) -> str:
        brief = ctx.deps.task_brief
        snapshot = ctx.deps.project_snapshot
        acceptance = _format_list(brief.acceptance_criteria)
        scope = _format_list([artifact.value for artifact in brief.scope])
        starting_points = _format_list(brief.suggested_starting_points)
        lean_files = _format_list([record.path for record in snapshot.lean_files])
        return "\n".join(
            [
                f"Task id: {brief.task_id}",
                f"Title: {brief.title}",
                f"Description: {brief.description}",
                f"Acceptance criteria: {acceptance}",
                f"Scope: {scope}",
                f"Local context: {brief.local_context or '(none)'}",
                f"Suggested starting points: {starting_points}",
                f"Project root: {snapshot.project_root}",
                f"Lean files in snapshot: {lean_files}",
            ]
        )

    return agent


class WorkerService:
    def __init__(self, config: FrameworkConfig | FrameworkPaths) -> None:
        self.config = config if isinstance(config, FrameworkConfig) else FrameworkConfig(paths=config)
        self.snapshot_service = ProjectSnapshotService(self.config)
        self.task_service = TaskService(self.config.paths.tasks_dir)

    def build_deps(
        self,
        snapshot: ProjectSnapshot,
        task_brief,
        toolkit_client: AsyncAftkClient,
    ) -> WorkerDeps:
        return WorkerDeps(
            config=self.config,
            project_snapshot=snapshot,
            task_brief=task_brief,
            toolkit_client=toolkit_client,
        )

    def prepare_snapshot(self, snapshot: ProjectSnapshot | None = None) -> ProjectSnapshot:
        if snapshot is not None:
            self.snapshot_service.store.save_snapshot(snapshot)
            return snapshot
        if self.snapshot_service.store.has_snapshot():
            return self.snapshot_service.load_snapshot()
        return self.snapshot_service.build_and_save_snapshot()

    async def run_worker(
        self,
        toolkit_client: AsyncAftkClient,
        *,
        task_brief,
        model: Any | None = None,
        agent: Agent[WorkerDeps, WorkerReport] | None = None,
        snapshot: ProjectSnapshot | None = None,
        user_prompt: str = DEFAULT_WORKER_USER_PROMPT,
        recorder: CodingActionRecorder | None = None,
        toolsets: Sequence[Any] | None = None,
    ) -> AgentRunResult[WorkerReport]:
        chosen_snapshot = self.prepare_snapshot(snapshot)
        chosen_agent = (
            build_worker_agent(toolsets=()) if agent is None and toolsets is not None else build_worker_agent()
        ) if agent is None else agent
        run_model = _resolve_run_model(model=model, agent=agent, configured_model=self.config.models.worker)
        chosen_toolsets = (
            list(build_worker_toolsets(self.config, chosen_snapshot, toolkit_client, recorder=recorder))
            if toolsets is None
            else list(toolsets)
        )
        run_kwargs: dict[str, Any] = {
            "deps": self.build_deps(chosen_snapshot, task_brief, toolkit_client),
            "toolsets": chosen_toolsets,
        }
        if run_model is not None:
            run_kwargs["model"] = run_model
        return await chosen_agent.run(user_prompt, **run_kwargs)


def _default_worker_toolset(ctx: RunContext[WorkerDeps]) -> Any:
    return CombinedToolset(
        toolsets=list(build_worker_toolsets(ctx.deps.config, ctx.deps.project_snapshot, ctx.deps.toolkit_client))
    )


def _resolve_run_model(
    *,
    model: Any | None,
    agent: Agent[WorkerDeps, WorkerReport] | None,
    configured_model: str | None,
) -> Any | None:
    if model is not None:
        return model
    if agent is not None:
        return None
    if configured_model is None:
        raise ValueError("worker model is not configured; pass model=... or set config.models.worker")
    return configured_model


def _format_list(values: Sequence[object], *, limit: int = 12) -> str:
    if not values:
        return "(none)"
    rendered = [str(value) for value in values[:limit]]
    if len(values) > limit:
        rendered.append(f"... (+{len(values) - limit} more)")
    return ", ".join(rendered)


__all__ = [
    "DEFAULT_WORKER_USER_PROMPT",
    "WorkerService",
    "build_worker_agent",
]
