from __future__ import annotations

from datetime import datetime, timezone
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


TASK_RUN_SCHEMA_VERSION = 1


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class TaskModel(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class TaskLifecycleStatus(StrEnum):
    pending = "pending"
    running = "running"
    completed = "completed"
    failed = "failed"
    canceled = "canceled"


class TaskSchedulerStatus(StrEnum):
    blocked = "blocked"
    ready = "ready"
    running = "running"
    completed = "completed"
    failed = "failed"
    canceled = "canceled"


class TaskAttemptStatus(StrEnum):
    running = "running"
    completed = "completed"
    failed = "failed"
    canceled = "canceled"


class TaskExecutionStatus(StrEnum):
    completed = "completed"
    failed = "failed"
    canceled = "canceled"


class TaskArtifact(TaskModel):
    kind: str = Field(min_length=1)
    label: str | None = None
    value: Any = None
    created_at: datetime = Field(default_factory=utc_now)
    metadata: dict[str, Any] = Field(default_factory=dict)


class TaskAttempt(TaskModel):
    attempt: int = Field(ge=1)
    started_at: datetime = Field(default_factory=utc_now)
    finished_at: datetime | None = None
    runner_id: str | None = None
    status: TaskAttemptStatus = TaskAttemptStatus.running
    summary: str | None = None
    error_message: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def _validate_finished_state(self) -> TaskAttempt:
        if self.status == TaskAttemptStatus.running:
            if self.finished_at is not None:
                raise ValueError("running attempts must not have finished_at set")
        elif self.finished_at is None:
            raise ValueError("finished attempts must set finished_at")
        return self


class TaskSpec(TaskModel):
    id: str = Field(min_length=1)
    kind: str = Field(min_length=1)
    title: str = Field(min_length=1)
    description: str | None = None
    payload: dict[str, Any] = Field(default_factory=dict)
    tags: list[str] = Field(default_factory=list)
    priority: int = 0
    depends_on: list[str] = Field(default_factory=list)
    max_attempts: int | None = Field(default=None, ge=1)
    metadata: dict[str, Any] = Field(default_factory=dict)

    @field_validator("depends_on")
    @classmethod
    def _validate_dependencies(cls, value: list[str]) -> list[str]:
        seen: set[str] = set()
        cleaned: list[str] = []
        for dependency_id in value:
            dep = dependency_id.strip()
            if not dep:
                raise ValueError("dependency ids must not be blank")
            if dep in seen:
                raise ValueError(f"duplicate dependency id: {dep}")
            seen.add(dep)
            cleaned.append(dep)
        return cleaned


class TaskRecord(TaskSpec):
    status: TaskLifecycleStatus = TaskLifecycleStatus.pending
    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)
    claimed_by: str | None = None
    started_at: datetime | None = None
    finished_at: datetime | None = None
    attempts: list[TaskAttempt] = Field(default_factory=list)
    artifacts: list[TaskArtifact] = Field(default_factory=list)
    result_summary: str | None = None
    last_error: str | None = None

    @model_validator(mode="after")
    def _validate_runtime_state(self) -> TaskRecord:
        if self.status == TaskLifecycleStatus.running:
            if self.started_at is None:
                raise ValueError("running tasks must set started_at")
            if self.finished_at is not None:
                raise ValueError("running tasks must not set finished_at")
        else:
            if self.claimed_by is not None:
                raise ValueError("only running tasks may be claimed")
            if self.status in {
                TaskLifecycleStatus.completed,
                TaskLifecycleStatus.failed,
                TaskLifecycleStatus.canceled,
            } and self.finished_at is None:
                raise ValueError("terminal tasks must set finished_at")
        return self


class TaskRunState(TaskModel):
    schema_version: int = TASK_RUN_SCHEMA_VERSION
    run_id: str = Field(min_length=1)
    created_at: datetime = Field(default_factory=utc_now)
    updated_at: datetime = Field(default_factory=utc_now)
    tasks: dict[str, TaskRecord] = Field(default_factory=dict)
    metadata: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def _validate_task_ids(self) -> TaskRunState:
        for task_id, task in self.tasks.items():
            if task.id != task_id:
                raise ValueError(f"task id mismatch for key {task_id!r}: found {task.id!r}")
        return self


class TaskExecutionResult(TaskModel):
    status: TaskExecutionStatus = TaskExecutionStatus.completed
    summary: str | None = None
    error_message: str | None = None
    artifacts: list[TaskArtifact] = Field(default_factory=list)
    metadata: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def _validate_failed_execution(self) -> TaskExecutionResult:
        if self.status == TaskExecutionStatus.failed and not self.error_message:
            raise ValueError("failed execution results must include error_message")
        return self
