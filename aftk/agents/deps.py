from __future__ import annotations

from dataclasses import dataclass

from aftk.config import FrameworkConfig
from aftk.project import ProjectSnapshot
from aftk.tasks import TaskState
from aftk_client import AsyncAftkClient

from aftk.agents.models import WorkerReport, WorkerTaskBrief


@dataclass(frozen=True, slots=True)
class InitializerDeps:
    config: FrameworkConfig
    project_snapshot: ProjectSnapshot
    toolkit_client: AsyncAftkClient


@dataclass(frozen=True, slots=True)
class OrchestratorDeps:
    config: FrameworkConfig
    project_snapshot: ProjectSnapshot
    task_snapshot: TaskState
    toolkit_client: AsyncAftkClient
    last_worker_report: WorkerReport | None = None


@dataclass(frozen=True, slots=True)
class WorkerDeps:
    config: FrameworkConfig
    project_snapshot: ProjectSnapshot
    task_brief: WorkerTaskBrief
    toolkit_client: AsyncAftkClient


AgentDeps = InitializerDeps | OrchestratorDeps | WorkerDeps


__all__ = [
    "AgentDeps",
    "InitializerDeps",
    "OrchestratorDeps",
    "WorkerDeps",
]
