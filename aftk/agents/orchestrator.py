from __future__ import annotations

from collections import Counter
from typing import Any, Sequence

from pydantic_ai import Agent, RunContext
from pydantic_ai.agent import AgentRunResult
from pydantic_ai.toolsets import CombinedToolset

from aftk.agents.deps import OrchestratorDeps
from aftk.agents.models import OrchestratorDecision, WorkerReport
from aftk.agents.tools import build_orchestrator_toolsets
from aftk.config import FrameworkConfig, FrameworkPaths
from aftk.project import ProjectSnapshot, ProjectSnapshotService
from aftk.tasks import Blocker, Task, TaskService, TaskState, TaskStatus
from aftk_client import AsyncAftkClient


DEFAULT_ORCHESTRATOR_USER_PROMPT = (
    "Review the current project state and return the next OrchestratorDecision. Either mark the project complete, "
    "or choose the next ready task and provide a focused worker brief along with any needed task patches or new tasks."
)
_ORCHESTRATOR_ROLE_INSTRUCTIONS = """
You are the orchestrator agent for the AFTK autoformalization framework.

Your job is to manage the global plan without doing detailed task execution yourself.

Requirements:
- inspect the current task graph and latest project context before deciding what should happen next
- choose only tasks that are actually ready for worker execution
- keep tasks small, local, and dependency-aware
- interpret the latest worker report when present and update the graph accordingly
- only propose structured task changes; the runner validates and applies them
- never assume you can mutate persistent state directly
- do not use coding tools or attempt code execution yourself
- only mark project_done when no required non-terminal work remains after your proposed patches and new tasks
""".strip()


def build_orchestrator_agent(
    model: Any | None = None,
    *,
    toolsets: Sequence[Any] | None = None,
) -> Agent[OrchestratorDeps, OrchestratorDecision]:
    configured_toolsets = [_default_orchestrator_toolset] if toolsets is None else list(toolsets)
    agent = Agent(
        model,
        name="aftk_orchestrator",
        deps_type=OrchestratorDeps,
        output_type=OrchestratorDecision,
        instructions=_ORCHESTRATOR_ROLE_INSTRUCTIONS,
        toolsets=configured_toolsets,
        defer_model_check=model is None,
    )

    @agent.instructions
    def add_orchestrator_context(ctx: RunContext[OrchestratorDeps]) -> str:
        snapshot = ctx.deps.project_snapshot
        task_summary = _format_task_snapshot(ctx.deps.task_snapshot)
        last_report = _format_worker_report(ctx.deps.last_worker_report)
        return "\n".join(
            [
                f"Project root: {snapshot.project_root}",
                f"Entrypoint path: {snapshot.entrypoint_path}",
                f"Lakefile path: {snapshot.lakefile_path}",
                f"Lean file count: {len(snapshot.lean_files)}",
                f"Source file count: {len(snapshot.source_inventory)}",
                "Current task snapshot:",
                task_summary,
                "Latest worker report:",
                last_report,
            ]
        )

    return agent


class OrchestratorService:
    def __init__(self, config: FrameworkConfig | FrameworkPaths) -> None:
        self.config = config if isinstance(config, FrameworkConfig) else FrameworkConfig(paths=config)
        self.snapshot_service = ProjectSnapshotService(self.config)
        self.task_service = TaskService(self.config.paths.tasks_dir)

    def build_deps(
        self,
        snapshot: ProjectSnapshot,
        task_snapshot: TaskState,
        toolkit_client: AsyncAftkClient,
        *,
        last_worker_report: WorkerReport | None = None,
    ) -> OrchestratorDeps:
        return OrchestratorDeps(
            config=self.config,
            project_snapshot=snapshot,
            task_snapshot=task_snapshot,
            toolkit_client=toolkit_client,
            last_worker_report=last_worker_report,
        )

    def prepare_snapshot(self, snapshot: ProjectSnapshot | None = None) -> ProjectSnapshot:
        if snapshot is not None:
            self.snapshot_service.store.save_snapshot(snapshot)
            return snapshot
        if self.snapshot_service.store.has_snapshot():
            return self.snapshot_service.load_snapshot()
        return self.snapshot_service.build_and_save_snapshot()

    async def run_orchestrator(
        self,
        toolkit_client: AsyncAftkClient,
        *,
        task_snapshot: TaskState | None = None,
        last_worker_report: WorkerReport | None = None,
        model: Any | None = None,
        agent: Agent[OrchestratorDeps, OrchestratorDecision] | None = None,
        snapshot: ProjectSnapshot | None = None,
        user_prompt: str = DEFAULT_ORCHESTRATOR_USER_PROMPT,
        toolsets: Sequence[Any] | None = None,
    ) -> AgentRunResult[OrchestratorDecision]:
        chosen_snapshot = self.prepare_snapshot(snapshot)
        chosen_task_snapshot = self.task_service.load_state() if task_snapshot is None else task_snapshot
        chosen_agent = (
            build_orchestrator_agent(toolsets=()) if agent is None and toolsets is not None else build_orchestrator_agent()
        ) if agent is None else agent
        run_model = _resolve_run_model(model=model, agent=agent, configured_model=self.config.models.orchestrator)
        run_kwargs: dict[str, Any] = {
            "deps": self.build_deps(
                chosen_snapshot,
                chosen_task_snapshot,
                toolkit_client,
                last_worker_report=last_worker_report,
            )
        }
        if run_model is not None:
            run_kwargs["model"] = run_model
        if toolsets is not None:
            run_kwargs["toolsets"] = list(toolsets)
        return await chosen_agent.run(user_prompt, **run_kwargs)


def _default_orchestrator_toolset(ctx: RunContext[OrchestratorDeps]) -> Any:
    return CombinedToolset(toolsets=list(build_orchestrator_toolsets(ctx.deps.project_snapshot, ctx.deps.toolkit_client)))


def _resolve_run_model(
    *,
    model: Any | None,
    agent: Agent[OrchestratorDeps, OrchestratorDecision] | None,
    configured_model: str | None,
) -> Any | None:
    if model is not None:
        return model
    if agent is not None:
        return None
    if configured_model is None:
        raise ValueError("orchestrator model is not configured; pass model=... or set config.models.orchestrator")
    return configured_model


def _format_task_snapshot(state: TaskState, *, limit: int = 40) -> str:
    counts = Counter(task.status.value for task in state.tasks.values())
    lines = [
        f"- revision: {state.revision}",
        f"- total tasks: {len(state.tasks)}",
        f"- ready: {counts.get(TaskStatus.READY.value, 0)}",
        f"- planned: {counts.get(TaskStatus.PLANNED.value, 0)}",
        f"- in_progress: {counts.get(TaskStatus.IN_PROGRESS.value, 0)}",
        f"- blocked: {counts.get(TaskStatus.BLOCKED.value, 0)}",
        f"- completed: {counts.get(TaskStatus.COMPLETED.value, 0)}",
        f"- failed: {counts.get(TaskStatus.FAILED.value, 0)}",
        f"- cancelled: {counts.get(TaskStatus.CANCELLED.value, 0)}",
        "- tasks:",
    ]
    tasks = sorted(state.tasks.values(), key=lambda task: task.id)
    for task in tasks[:limit]:
        lines.append(_format_task_line(task))
    if len(tasks) > limit:
        lines.append(f"  - ... (+{len(tasks) - limit} more tasks)")
    return "\n".join(lines)


def _format_task_line(task: Task) -> str:
    dependencies = ", ".join(task.depends_on) if task.depends_on else "none"
    blockers = "; ".join(_format_blocker(blocker) for blocker in task.blockers) if task.blockers else "none"
    scope = ", ".join(artifact.value for artifact in task.scope) if task.scope else "none"
    return (
        f"  - {task.id} [{task.status.value}] {task.title} | priority={task.priority.value} | "
        f"depends_on={dependencies} | blockers={blockers} | scope={scope}"
    )


def _format_blocker(blocker: Blocker) -> str:
    if blocker.task_id is None:
        return blocker.summary
    return f"{blocker.summary} (task: {blocker.task_id})"


def _format_worker_report(report: WorkerReport | None) -> str:
    if report is None:
        return "- none"
    followups = ", ".join(task.title for task in report.followup_tasks) if report.followup_tasks else "none"
    blockers = "; ".join(_format_blocker(blocker) for blocker in report.blockers) if report.blockers else "none"
    evidence = " | ".join(report.evidence[:5]) if report.evidence else "none"
    handoff = report.handoff_notes or "none"
    return "\n".join(
        [
            f"- outcome: {report.outcome.value}",
            f"- summary: {report.summary}",
            f"- evidence: {evidence}",
            f"- blockers: {blockers}",
            f"- proposed follow-up tasks: {followups}",
            f"- handoff notes: {handoff}",
        ]
    )


__all__ = [
    "DEFAULT_ORCHESTRATOR_USER_PROMPT",
    "OrchestratorService",
    "build_orchestrator_agent",
]
