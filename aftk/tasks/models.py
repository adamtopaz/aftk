from __future__ import annotations

from datetime import datetime, timezone
from enum import StrEnum
from typing import Annotated, Any, Self

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, field_validator, model_validator


NonEmptyString = Annotated[str, Field(min_length=1)]
TaskId = Annotated[str, Field(pattern=r"^task-\d+$")]
AttemptId = Annotated[str, Field(min_length=1)]
SummaryValue = str | int | float | bool | None


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class TaskModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class TaskStatus(StrEnum):
    PLANNED = "planned"
    READY = "ready"
    IN_PROGRESS = "in_progress"
    BLOCKED = "blocked"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class TaskPriority(StrEnum):
    LOW = "low"
    NORMAL = "normal"
    HIGH = "high"
    URGENT = "urgent"


class ArtifactKind(StrEnum):
    FILE = "file"
    DECLARATION = "declaration"
    KNOWLEDGEBASE_NODE = "knowledgebase_node"
    SOURCE = "source"
    OTHER = "other"


class BlockerKind(StrEnum):
    TASK = "task"
    INFORMATION = "information"
    RESOURCE = "resource"
    EXTERNAL = "external"


class TaskAttemptStatus(StrEnum):
    RUNNING = "running"
    COMPLETED = "completed"
    PARTIAL = "partial"
    BLOCKED = "blocked"
    FAILED = "failed"


class TaskEventKind(StrEnum):
    TASK_CREATED = "task_created"
    TASK_PATCHED = "task_patched"
    TASK_CLAIMED = "task_claimed"
    ATTEMPT_STARTED = "attempt_started"
    ATTEMPT_FINISHED = "attempt_finished"
    TASK_RECOVERED = "task_recovered"
    TASK_DELETED = "task_deleted"


class ArtifactRef(TaskModel):
    kind: ArtifactKind
    value: NonEmptyString


class Blocker(TaskModel):
    kind: BlockerKind
    summary: NonEmptyString
    task_id: TaskId | None = None

    @model_validator(mode="after")
    def validate_task_blocker(self) -> Self:
        if self.kind is BlockerKind.TASK and self.task_id is None:
            raise ValueError("task blockers must include task_id")
        return self


class TaskNote(TaskModel):
    author: NonEmptyString
    message: NonEmptyString
    timestamp: AwareDatetime = Field(default_factory=utc_now)


class Task(TaskModel):
    id: TaskId
    title: NonEmptyString
    description: NonEmptyString
    kind: NonEmptyString
    status: TaskStatus
    priority: TaskPriority = TaskPriority.NORMAL
    acceptance_criteria: list[NonEmptyString] = Field(default_factory=list)
    depends_on: list[TaskId] = Field(default_factory=list)
    blockers: list[Blocker] = Field(default_factory=list)
    scope: list[ArtifactRef] = Field(default_factory=list)
    context_summary: NonEmptyString | None = None
    notes: list[TaskNote] = Field(default_factory=list)
    created_by: NonEmptyString
    updated_by: NonEmptyString
    current_attempt_id: AttemptId | None = None
    attempt_count: int = Field(default=0, ge=0)
    created_at: AwareDatetime = Field(default_factory=utc_now)
    updated_at: AwareDatetime = Field(default_factory=utc_now)

    @field_validator("depends_on")
    @classmethod
    def validate_unique_dependencies(cls, value: list[TaskId]) -> list[TaskId]:
        if len(value) != len(set(value)):
            raise ValueError("depends_on must not contain duplicates")
        return value

    @model_validator(mode="after")
    def validate_status_fields(self) -> Self:
        if self.status is TaskStatus.IN_PROGRESS and self.current_attempt_id is None:
            raise ValueError("in_progress tasks must include current_attempt_id")
        if self.status is not TaskStatus.IN_PROGRESS and self.current_attempt_id is not None:
            raise ValueError("current_attempt_id is only valid for in_progress tasks")
        if self.status is TaskStatus.BLOCKED and not self.blockers:
            raise ValueError("blocked tasks must include at least one blocker")
        if self.updated_at < self.created_at:
            raise ValueError("updated_at must not be earlier than created_at")
        return self


class TaskDraft(TaskModel):
    title: NonEmptyString
    description: NonEmptyString
    kind: NonEmptyString
    priority: TaskPriority = TaskPriority.NORMAL
    acceptance_criteria: list[NonEmptyString] = Field(default_factory=list)
    depends_on: list[TaskId] = Field(default_factory=list)
    blockers: list[Blocker] = Field(default_factory=list)
    scope: list[ArtifactRef] = Field(default_factory=list)
    context_summary: NonEmptyString | None = None

    @field_validator("depends_on")
    @classmethod
    def validate_unique_dependencies(cls, value: list[TaskId]) -> list[TaskId]:
        if len(value) != len(set(value)):
            raise ValueError("depends_on must not contain duplicates")
        return value


class TaskPatch(TaskModel):
    task_id: TaskId
    new_status: TaskStatus | None = None
    add_dependencies: list[TaskId] = Field(default_factory=list)
    remove_dependencies: list[TaskId] = Field(default_factory=list)
    blockers: list[Blocker] | None = None
    append_notes: list[NonEmptyString] = Field(default_factory=list)
    context_summary: NonEmptyString | None = None
    priority: TaskPriority | None = None

    @field_validator("add_dependencies", "remove_dependencies")
    @classmethod
    def validate_unique_dependency_changes(cls, value: list[TaskId]) -> list[TaskId]:
        if len(value) != len(set(value)):
            raise ValueError("dependency changes must not contain duplicates")
        return value

    @model_validator(mode="after")
    def validate_dependency_changes(self) -> Self:
        overlap = set(self.add_dependencies) & set(self.remove_dependencies)
        if overlap:
            ids = ", ".join(sorted(overlap))
            raise ValueError(f"dependencies cannot be added and removed in the same patch: {ids}")
        return self


class TaskAttempt(TaskModel):
    id: AttemptId
    task_id: TaskId
    worker_kind: NonEmptyString
    status: TaskAttemptStatus
    started_at: AwareDatetime = Field(default_factory=utc_now)
    finished_at: AwareDatetime | None = None
    run_id: NonEmptyString | None = None
    report_path: NonEmptyString | None = None
    transcript_path: NonEmptyString | None = None
    llm_call_log_path: NonEmptyString | None = None
    tool_call_log_path: NonEmptyString | None = None
    usage_summary: dict[str, SummaryValue] | None = None
    cost_summary: dict[str, SummaryValue] | None = None
    summary: NonEmptyString | None = None

    @model_validator(mode="after")
    def validate_timestamps(self) -> Self:
        if self.status is TaskAttemptStatus.RUNNING and self.finished_at is not None:
            raise ValueError("running attempts must not have finished_at")
        if self.status is not TaskAttemptStatus.RUNNING and self.finished_at is None:
            raise ValueError("finished_at is required once an attempt is no longer running")
        if self.finished_at is not None and self.finished_at < self.started_at:
            raise ValueError("finished_at must not be earlier than started_at")
        return self


class TaskEvent(TaskModel):
    kind: TaskEventKind
    timestamp: AwareDatetime = Field(default_factory=utc_now)
    revision: int = Field(ge=0)
    task_id: TaskId | None = None
    attempt_id: AttemptId | None = None
    actor: NonEmptyString | None = None
    payload: dict[str, Any] = Field(default_factory=dict)


class TaskState(TaskModel):
    revision: int = Field(default=0, ge=0)
    tasks: dict[TaskId, Task] = Field(default_factory=dict)
    created_at: AwareDatetime = Field(default_factory=utc_now)
    updated_at: AwareDatetime = Field(default_factory=utc_now)

    @model_validator(mode="after")
    def validate_task_keys(self) -> Self:
        if self.updated_at < self.created_at:
            raise ValueError("updated_at must not be earlier than created_at")
        for task_id, task in self.tasks.items():
            if task_id != task.id:
                raise ValueError(f"task key {task_id!r} does not match task.id {task.id!r}")
        return self

    @classmethod
    def empty(cls, *, revision: int = 0, now: datetime | None = None) -> TaskState:
        timestamp = utc_now() if now is None else now
        return cls(revision=revision, tasks={}, created_at=timestamp, updated_at=timestamp)


__all__ = [
    "ArtifactKind",
    "ArtifactRef",
    "AttemptId",
    "Blocker",
    "BlockerKind",
    "NonEmptyString",
    "SummaryValue",
    "Task",
    "TaskAttempt",
    "TaskAttemptStatus",
    "TaskDraft",
    "TaskEvent",
    "TaskEventKind",
    "TaskId",
    "TaskModel",
    "TaskNote",
    "TaskPatch",
    "TaskPriority",
    "TaskState",
    "TaskStatus",
    "utc_now",
]
