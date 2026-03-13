from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from aftk.tasks.models import TaskAttemptStatus, TaskLifecycleStatus, TaskSchedulerStatus, TaskSpec


class ToolkitModel(BaseModel):
    """Base model for task-toolkit inputs and outputs."""

    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class TaskToolErrorInfo(ToolkitModel):
    """Structured error information returned to an agent."""

    kind: str = Field(description="Stable machine-readable error kind.")
    message: str = Field(description="Human-readable explanation of the tool failure.")
    retryable: bool = Field(description="Whether retrying or adjusting the request could succeed.")
    suggested_action: str | None = Field(
        default=None,
        description="Short machine-readable suggestion describing what the agent should try next.",
    )
    details: dict[str, Any] | None = Field(
        default=None,
        description="Optional structured debugging or task-domain details about the failure.",
    )


class TaskToolSuccess(ToolkitModel):
    """Successful tool-call envelope."""

    ok: Literal[True] = True
    tool: str = Field(description="The tool name that produced this result.")
    data: Any = Field(description="Tool-specific success payload.")


class TaskToolFailure(ToolkitModel):
    """Failed tool-call envelope."""

    ok: Literal[False] = False
    tool: str = Field(description="The tool name that failed.")
    error: TaskToolErrorInfo = Field(description="Structured failure information.")


TaskToolResult = TaskToolSuccess | TaskToolFailure


class TaskIdInput(ToolkitModel):
    """Input for tools that target a single task id."""

    task_id: str = Field(description="Identifier of the task to inspect.")


class TaskListInput(ToolkitModel):
    """Input for tools that return ordered task lists."""

    limit: int | None = Field(
        default=None,
        ge=1,
        description="Optional maximum number of task summaries to return.",
    )


class TaskTargetInput(ToolkitModel):
    """Input for tools that may default to the current bound task."""

    task_id: str | None = Field(
        default=None,
        description="Optional task id to target. Omit this to use the current bound task when available.",
    )


class TaskNoteInput(TaskTargetInput):
    """Input for attaching a note artifact to a task."""

    text: str = Field(description="Plain-text note content to append to the task.")
    metadata: dict[str, Any] = Field(
        default_factory=dict,
        description="Optional structured metadata to store alongside the note artifact.",
    )


class TaskArtifactInput(TaskTargetInput):
    """Input for attaching a structured artifact to a task."""

    kind: str = Field(description="Machine-readable artifact kind, such as 'note', 'output', or 'analysis'.")
    label: str | None = Field(default=None, description="Optional short human-readable artifact label.")
    value: Any = Field(description="Artifact payload to attach to the task.")
    metadata: dict[str, Any] = Field(
        default_factory=dict,
        description="Optional structured metadata to store alongside the artifact.",
    )


class TaskSpecInput(ToolkitModel):
    """Task-spec payload used for validated task proposals."""

    id: str = Field(description="Stable identifier for the proposed task.")
    kind: str = Field(description="Machine-readable task kind for the proposed task.")
    title: str = Field(description="Short human-readable title for the proposed task.")
    description: str | None = Field(default=None, description="Optional longer description of the proposed work.")
    payload: dict[str, Any] = Field(
        default_factory=dict,
        description="Structured task-specific payload data for the proposal.",
    )
    tags: list[str] = Field(default_factory=list, description="Optional tags associated with the proposed task.")
    priority: int = Field(default=0, description="Relative priority used when scheduling the proposed task.")
    depends_on: list[str] = Field(
        default_factory=list,
        description="Optional list of task ids that the proposed task depends on.",
    )
    max_attempts: int | None = Field(
        default=None,
        ge=1,
        description="Optional maximum number of execution attempts allowed for the proposed task.",
    )
    metadata: dict[str, Any] = Field(
        default_factory=dict,
        description="Optional structured metadata for the proposed task.",
    )

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

    def to_task_spec(self) -> TaskSpec:
        """Convert the described input payload to a canonical task specification."""

        return TaskSpec(**self.model_dump())


class TaskProposalInput(TaskTargetInput):
    """Input for recording a structured batch of proposed follow-up tasks."""

    proposals: list[TaskSpecInput] = Field(
        min_length=1,
        description="Non-empty list of validated task-spec payloads to record as a proposal batch.",
    )
    rationale: str | None = Field(
        default=None,
        description="Optional explanation of why these follow-up tasks are being proposed.",
    )
    metadata: dict[str, Any] = Field(
        default_factory=dict,
        description="Optional structured metadata to store alongside the proposal artifact.",
    )


class TaskAttemptView(ToolkitModel):
    """Lightweight agent-facing view of one task attempt."""

    attempt: int = Field(description="1-based attempt number.")
    status: TaskAttemptStatus = Field(description="Lifecycle status of this attempt.")
    started_at: datetime = Field(description="Timestamp when this attempt started.")
    finished_at: datetime | None = Field(default=None, description="Timestamp when this attempt finished, if any.")
    runner_id: str | None = Field(default=None, description="Runner identifier recorded for this attempt, if any.")
    summary: str | None = Field(default=None, description="Optional short summary recorded for this attempt.")
    error_message: str | None = Field(default=None, description="Optional error message recorded for this attempt.")
    metadata: dict[str, Any] = Field(default_factory=dict, description="Structured metadata attached to this attempt.")


class TaskArtifactView(ToolkitModel):
    """Lightweight agent-facing view of one task artifact."""

    kind: str = Field(description="Machine-readable artifact kind.")
    label: str | None = Field(default=None, description="Optional short human-readable artifact label.")
    value: Any = Field(description="Artifact payload value.")
    created_at: datetime = Field(description="Timestamp when the artifact was created.")
    metadata: dict[str, Any] = Field(default_factory=dict, description="Structured metadata attached to the artifact.")


class TaskSummaryView(ToolkitModel):
    """Lightweight agent-facing summary of a task."""

    id: str = Field(description="Task identifier.")
    kind: str = Field(description="Machine-readable task kind.")
    title: str = Field(description="Human-readable task title.")
    lifecycle_status: TaskLifecycleStatus = Field(description="Stored lifecycle status of the task.")
    scheduler_status: TaskSchedulerStatus = Field(description="Derived scheduler status of the task.")
    priority: int = Field(description="Relative task priority used for deterministic ordering.")
    depends_on: list[str] = Field(description="Direct dependency task ids for this task.")
    result_summary: str | None = Field(default=None, description="Optional final or latest summary for the task.")
    last_error: str | None = Field(default=None, description="Optional latest error message recorded for the task.")
    attempt_count: int = Field(description="Number of execution attempts recorded for the task.")
    max_attempts: int | None = Field(default=None, description="Optional maximum number of allowed attempts.")


class TaskDetailView(TaskSummaryView):
    """Richer agent-facing detail view of a task."""

    description: str | None = Field(default=None, description="Optional longer description of the task.")
    payload: dict[str, Any] = Field(description="Structured task payload data.")
    tags: list[str] = Field(description="Tags associated with the task.")
    metadata: dict[str, Any] = Field(description="Structured task metadata.")
    claimed_by: str | None = Field(default=None, description="Runner currently claiming the task, if any.")
    created_at: datetime = Field(description="Timestamp when the task record was created.")
    updated_at: datetime = Field(description="Timestamp when the task record was last updated.")
    started_at: datetime | None = Field(default=None, description="Timestamp when the current or last run started, if any.")
    finished_at: datetime | None = Field(default=None, description="Timestamp when the task reached its current terminal state, if any.")
    dependencies: list[TaskSummaryView] = Field(description="Direct dependency task summaries.")
    attempts: list[TaskAttemptView] = Field(description="Recorded attempt history for the task.")
    artifacts: list[TaskArtifactView] = Field(description="Artifacts attached to the task.")


class TaskListView(ToolkitModel):
    """Ordered list of task summaries."""

    total_tasks: int = Field(description="Total number of tasks in the underlying list before any limit is applied.")
    tasks_returned: int = Field(description="Number of task summaries returned in this payload.")
    tasks: list[TaskSummaryView] = Field(description="Ordered task summaries.")


class TaskRunSummaryView(ToolkitModel):
    """Run-wide summary view for the task manager."""

    run_id: str = Field(description="Task-run identifier.")
    current_task_id: str | None = Field(default=None, description="Current bound task id for this toolkit instance, if any.")
    total_tasks: int = Field(description="Total number of tasks in the run.")
    tasks_returned: int = Field(description="Number of task summaries included in this summary payload.")
    counts_by_lifecycle_status: dict[str, int] = Field(
        description="Counts of tasks grouped by stored lifecycle status.",
    )
    counts_by_scheduler_status: dict[str, int] = Field(
        description="Counts of tasks grouped by derived scheduler status.",
    )
    metadata: dict[str, Any] = Field(description="Run-level metadata stored with the task run.")
    tasks: list[TaskSummaryView] = Field(description="Ordered task summaries for the run.")

