from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from pydantic import ValidationError

from aftk.tasks import (
    MissingDependencyError,
    TaskConflictError,
    TaskCycleError,
    TaskGraphError,
    TaskMappingError,
    TaskNotFoundError,
    TaskTransitionError,
)

from .models import TaskToolErrorInfo, TaskToolFailure


@dataclass(slots=True)
class TaskToolkitExecutionError(Exception):
    """Internal exception used for expected task-toolkit failures."""

    kind: str
    message: str
    retryable: bool
    suggested_action: str | None = None
    details: dict[str, Any] | None = None

    def __post_init__(self) -> None:
        Exception.__init__(self, self.message)


def failure_from_exception(tool_name: str, exc: Exception) -> TaskToolFailure:
    """Convert an expected failure into a structured tool result."""

    return TaskToolFailure(tool=tool_name, error=error_info_from_exception(exc))


def error_info_from_exception(exc: Exception) -> TaskToolErrorInfo:
    """Map an exception to an agent-facing error payload."""

    if isinstance(exc, TaskToolkitExecutionError):
        return TaskToolErrorInfo(
            kind=exc.kind,
            message=exc.message,
            retryable=exc.retryable,
            suggested_action=exc.suggested_action,
            details=exc.details,
        )

    if isinstance(exc, TaskNotFoundError):
        task_id = _task_id_from_not_found(exc)
        return TaskToolErrorInfo(
            kind="task_not_found",
            message=f"Task {task_id!r} was not found.",
            retryable=True,
            suggested_action="check_task_id",
            details={"task_id": task_id},
        )

    if isinstance(exc, TaskTransitionError):
        return TaskToolErrorInfo(
            kind="invalid_transition",
            message=str(exc),
            retryable=True,
            suggested_action="inspect_task_state",
        )

    if isinstance(exc, TaskConflictError):
        return TaskToolErrorInfo(
            kind="task_conflict",
            message=str(exc),
            retryable=True,
            suggested_action="resolve_task_conflict",
        )

    if isinstance(exc, MissingDependencyError):
        return TaskToolErrorInfo(
            kind="missing_dependency",
            message=str(exc),
            retryable=True,
            suggested_action="check_dependency_ids",
        )

    if isinstance(exc, TaskCycleError):
        return TaskToolErrorInfo(
            kind="cycle_detected",
            message=str(exc),
            retryable=True,
            suggested_action="remove_cycle",
        )

    if isinstance(exc, (TaskMappingError, TaskGraphError)):
        return TaskToolErrorInfo(
            kind="graph_error",
            message=str(exc),
            retryable=True,
            suggested_action="inspect_graph",
        )

    if isinstance(exc, ValidationError):
        return TaskToolErrorInfo(
            kind="invalid_payload",
            message="The task-tool payload did not pass validation.",
            retryable=True,
            suggested_action="fix_payload",
            details={"errors": exc.errors(include_url=False)},
        )

    return TaskToolErrorInfo(
        kind="task_tool_internal_error",
        message=str(exc) or exc.__class__.__name__,
        retryable=False,
        suggested_action="report_failure",
        details={"exception_type": exc.__class__.__name__},
    )


def _task_id_from_not_found(exc: TaskNotFoundError) -> str:
    if exc.args:
        raw = exc.args[0]
        if isinstance(raw, str):
            return raw
    return "<unknown>"
