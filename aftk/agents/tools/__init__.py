from __future__ import annotations

from typing import Any

from aftk.coding.logs import CodingActionRecorder
from aftk.config import FrameworkConfig, FrameworkPaths, PathLike
from aftk.project import ProjectSnapshot
from aftk_client import AsyncAftkClient

from aftk.agents.tools.coding import WorkerCodingTools, build_worker_coding_toolset
from aftk.agents.tools.project import ProjectContextTools, ProjectSnapshotSummary, build_project_context_toolset
from aftk.agents.tools.toolkit import ToolkitQueryTools, build_toolkit_query_toolset


def build_initializer_toolsets(
    project_snapshot: ProjectSnapshot,
    toolkit_client: AsyncAftkClient,
) -> tuple[Any, ...]:
    return (
        build_project_context_toolset(project_snapshot),
        build_toolkit_query_toolset(toolkit_client),
    )


def build_orchestrator_toolsets(
    project_snapshot: ProjectSnapshot,
    toolkit_client: AsyncAftkClient,
) -> tuple[Any, ...]:
    return build_initializer_toolsets(project_snapshot, toolkit_client)


def build_worker_toolsets(
    project: FrameworkConfig | FrameworkPaths | PathLike,
    project_snapshot: ProjectSnapshot,
    toolkit_client: AsyncAftkClient,
    *,
    recorder: CodingActionRecorder | None = None,
) -> tuple[Any, ...]:
    return (
        build_project_context_toolset(project_snapshot),
        build_toolkit_query_toolset(toolkit_client),
        build_worker_coding_toolset(project, recorder=recorder),
    )


__all__ = [
    "ProjectContextTools",
    "ProjectSnapshotSummary",
    "ToolkitQueryTools",
    "WorkerCodingTools",
    "build_initializer_toolsets",
    "build_orchestrator_toolsets",
    "build_project_context_toolset",
    "build_toolkit_query_toolset",
    "build_worker_coding_toolset",
    "build_worker_toolsets",
]
