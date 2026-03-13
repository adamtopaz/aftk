from __future__ import annotations

from typing import TYPE_CHECKING, Protocol

from aftk.tasks.models import TaskExecutionResult, TaskRecord

if TYPE_CHECKING:
    from aftk.tasks.manager import TaskManager


class TaskWorkerRunner(Protocol):
    """Protocol implemented by orchestrator-side worker runners."""

    async def run_task(self, manager: TaskManager, task: TaskRecord) -> TaskExecutionResult:
        """Execute work for a claimed task and return the normalized execution result."""

        ...
