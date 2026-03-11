from __future__ import annotations

from enum import StrEnum
from typing import Self

from pydantic import Field, model_validator

from aftk.config import FrameworkModel
from aftk.tasks import ArtifactRef, Blocker, NonEmptyString, Task, TaskDraft, TaskId, TaskPatch


class WorkerOutcome(StrEnum):
    COMPLETED = "completed"
    PARTIAL = "partial"
    BLOCKED = "blocked"
    FAILED = "failed"


class WorkerTaskBrief(FrameworkModel):
    task_id: TaskId
    title: NonEmptyString
    description: NonEmptyString
    acceptance_criteria: list[NonEmptyString] = Field(default_factory=list)
    scope: list[ArtifactRef] = Field(default_factory=list)
    local_context: str = ""
    suggested_starting_points: list[NonEmptyString] = Field(default_factory=list)

    @classmethod
    def from_task(
        cls,
        task: Task,
        *,
        local_context: str = "",
        suggested_starting_points: list[str] | None = None,
    ) -> WorkerTaskBrief:
        return cls(
            task_id=task.id,
            title=task.title,
            description=task.description,
            acceptance_criteria=list(task.acceptance_criteria),
            scope=list(task.scope),
            local_context=local_context,
            suggested_starting_points=[] if suggested_starting_points is None else list(suggested_starting_points),
        )


class InitializationResult(FrameworkModel):
    project_summary: NonEmptyString
    assumptions: list[NonEmptyString] = Field(default_factory=list)
    risks: list[NonEmptyString] = Field(default_factory=list)
    initial_tasks: list[TaskDraft] = Field(default_factory=list)


class OrchestratorDecision(FrameworkModel):
    project_done: bool
    selected_task_id: TaskId | None = None
    new_tasks: list[TaskDraft] = Field(default_factory=list)
    task_patches: list[TaskPatch] = Field(default_factory=list)
    worker_brief: WorkerTaskBrief | None = None
    rationale: NonEmptyString
    completion_summary: NonEmptyString | None = None

    @model_validator(mode="after")
    def validate_decision(self) -> Self:
        if self.project_done:
            if self.selected_task_id is not None or self.worker_brief is not None:
                raise ValueError("project_done decisions cannot select a worker task")
            if self.completion_summary is None:
                raise ValueError("project_done decisions must include completion_summary")
            return self

        if (self.selected_task_id is None) != (self.worker_brief is None):
            raise ValueError("selected_task_id and worker_brief must be provided together")
        if self.worker_brief is not None and self.worker_brief.task_id != self.selected_task_id:
            raise ValueError("worker_brief.task_id must match selected_task_id")
        return self


class WorkerReport(FrameworkModel):
    outcome: WorkerOutcome
    summary: NonEmptyString
    evidence: list[NonEmptyString] = Field(default_factory=list)
    changed_artifacts: list[ArtifactRef] = Field(default_factory=list)
    followup_tasks: list[TaskDraft] = Field(default_factory=list)
    blockers: list[Blocker] = Field(default_factory=list)
    handoff_notes: NonEmptyString | None = None

    @model_validator(mode="after")
    def validate_blocked_outcome(self) -> Self:
        if self.outcome is WorkerOutcome.BLOCKED and not self.blockers:
            raise ValueError("blocked worker reports must include at least one blocker")
        return self


__all__ = [
    "InitializationResult",
    "OrchestratorDecision",
    "WorkerOutcome",
    "WorkerReport",
    "WorkerTaskBrief",
]
