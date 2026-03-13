from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from aftk.tasks.models import (
    TaskAttemptStatus,
    TaskExecutionStatus,
    TaskLifecycleStatus,
    TaskSchedulerStatus,
    TaskSpec,
)
from aftk.tasks.proposals import TaskProposalStatus


class ToolkitModel(BaseModel):
    """Base model for orchestrator-toolkit inputs and outputs."""

    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class OrchestratorToolErrorInfo(ToolkitModel):
    """Structured error information returned to an orchestrator agent."""

    kind: str = Field(description="Stable machine-readable error kind.")
    message: str = Field(description="Human-readable explanation of the tool failure.")
    retryable: bool = Field(description="Whether retrying or adjusting the request could succeed.")
    suggested_action: str | None = Field(
        default=None,
        description="Short machine-readable suggestion describing what the agent should try next.",
    )
    details: dict[str, Any] | None = Field(
        default=None,
        description="Optional structured debugging or orchestration details about the failure.",
    )


class OrchestratorToolSuccess(ToolkitModel):
    """Successful orchestrator-tool envelope."""

    ok: Literal[True] = True
    tool: str = Field(description="The tool name that produced this result.")
    data: Any = Field(description="Tool-specific success payload.")


class OrchestratorToolFailure(ToolkitModel):
    """Failed orchestrator-tool envelope."""

    ok: Literal[False] = False
    tool: str = Field(description="The tool name that failed.")
    error: OrchestratorToolErrorInfo = Field(description="Structured failure information.")


OrchestratorToolResult = OrchestratorToolSuccess | OrchestratorToolFailure


class OrchTaskIdInput(ToolkitModel):
    """Input for tools that target one task id."""

    task_id: str = Field(description="Identifier of the task to inspect or mutate.")


class OrchTaskListInput(ToolkitModel):
    """Input for tools that return ordered task lists."""

    limit: int | None = Field(
        default=None,
        ge=1,
        description="Optional maximum number of task summaries to return.",
    )


class OrchTaskSpecInput(ToolkitModel):
    """Task-spec payload used for orchestrator graph mutations."""

    id: str = Field(description="Stable identifier for the task.")
    kind: str = Field(description="Machine-readable task kind.")
    title: str = Field(description="Short human-readable title for the task.")
    description: str | None = Field(default=None, description="Optional longer description of the task.")
    payload: dict[str, Any] = Field(
        default_factory=dict,
        description="Structured task-specific payload data.",
    )
    tags: list[str] = Field(default_factory=list, description="Optional tags associated with the task.")
    priority: int = Field(default=0, description="Relative priority used for scheduler ordering.")
    depends_on: list[str] = Field(
        default_factory=list,
        description="Optional list of dependency task ids for this task.",
    )
    max_attempts: int | None = Field(
        default=None,
        ge=1,
        description="Optional maximum number of execution attempts allowed for the task.",
    )
    metadata: dict[str, Any] = Field(
        default_factory=dict,
        description="Optional structured metadata for the task.",
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
        """Convert this input payload to a canonical task specification."""

        return TaskSpec(**self.model_dump())


class OrchAddTaskInput(ToolkitModel):
    """Input for adding one task to the run."""

    task: OrchTaskSpecInput = Field(description="Validated task specification to add to the run.")


class OrchAddTasksInput(ToolkitModel):
    """Input for adding several tasks to the run."""

    tasks: list[OrchTaskSpecInput] = Field(
        min_length=1,
        description="Non-empty list of validated task specifications to add to the run.",
    )


class OrchAddDependencyInput(ToolkitModel):
    """Input for adding a dependency edge between existing tasks."""

    task_id: str = Field(description="Task id that should depend on another task.")
    dependency_id: str = Field(description="Task id that must complete before task_id can run.")


class OrchTaskNoteInput(ToolkitModel):
    """Input for attaching an orchestrator note to a task."""

    task_id: str = Field(description="Task id that should receive the note artifact.")
    text: str = Field(description="Plain-text note content to append to the task.")
    metadata: dict[str, Any] = Field(
        default_factory=dict,
        description="Optional structured metadata to store alongside the note artifact.",
    )


class OrchTaskArtifactInput(ToolkitModel):
    """Input for attaching an orchestrator artifact to a task."""

    task_id: str = Field(description="Task id that should receive the artifact.")
    kind: str = Field(description="Machine-readable artifact kind, such as 'note', 'output', or 'analysis'.")
    label: str | None = Field(default=None, description="Optional short human-readable artifact label.")
    value: Any = Field(description="Artifact payload to attach to the task.")
    metadata: dict[str, Any] = Field(
        default_factory=dict,
        description="Optional structured metadata to store alongside the artifact.",
    )


class OrchArtifactSpecInput(ToolkitModel):
    """Artifact payload used inside completion and failure tool calls."""

    kind: str = Field(description="Machine-readable artifact kind.")
    label: str | None = Field(default=None, description="Optional short human-readable artifact label.")
    value: Any = Field(description="Artifact payload value.")
    metadata: dict[str, Any] = Field(
        default_factory=dict,
        description="Optional structured metadata attached to the artifact.",
    )


class OrchClaimTaskInput(ToolkitModel):
    """Input for claiming a ready task."""

    task_id: str = Field(description="Task id to claim for execution.")
    runner_id: str | None = Field(
        default=None,
        description="Optional runner identifier to record on the claimed task.",
    )


class OrchCompleteTaskInput(ToolkitModel):
    """Input for marking a running task completed."""

    task_id: str = Field(description="Task id to complete.")
    summary: str | None = Field(default=None, description="Optional short completion summary.")
    artifacts: list[OrchArtifactSpecInput] = Field(
        default_factory=list,
        description="Optional artifacts to attach while completing the task.",
    )
    metadata: dict[str, Any] = Field(
        default_factory=dict,
        description="Optional metadata to merge into the task and active attempt.",
    )


class OrchFailTaskInput(ToolkitModel):
    """Input for marking a running task failed."""

    task_id: str = Field(description="Task id to fail.")
    error_message: str = Field(description="Required error message explaining why the task failed.")
    summary: str | None = Field(default=None, description="Optional short failure summary.")
    artifacts: list[OrchArtifactSpecInput] = Field(
        default_factory=list,
        description="Optional artifacts to attach while failing the task.",
    )
    metadata: dict[str, Any] = Field(
        default_factory=dict,
        description="Optional metadata to merge into the task and active attempt.",
    )


class OrchCancelTaskInput(ToolkitModel):
    """Input for canceling a pending or running task."""

    task_id: str = Field(description="Task id to cancel.")
    summary: str | None = Field(default=None, description="Optional short cancelation summary.")
    metadata: dict[str, Any] = Field(
        default_factory=dict,
        description="Optional metadata to merge into the task and any active attempt.",
    )


class OrchRequeueTaskInput(ToolkitModel):
    """Input for requeueing a failed task."""

    task_id: str = Field(description="Task id to requeue.")
    clear_error: bool = Field(
        default=True,
        description="Whether to clear the task's last_error field while requeueing it.",
    )


class OrchProposalIdInput(ToolkitModel):
    """Input for tools that target one proposal id."""

    proposal_id: str = Field(description="Stable proposal identifier returned by orch_list_proposals.")


class OrchProposalListInput(ToolkitModel):
    """Input for listing task proposals across the run."""

    status: TaskProposalStatus | None = Field(
        default=TaskProposalStatus.pending,
        description="Optional proposal status filter. Omit this to list only pending proposals; pass null to list all proposals.",
    )
    limit: int | None = Field(
        default=None,
        ge=1,
        description="Optional maximum number of proposals to return.",
    )


class OrchProposalActionInput(ToolkitModel):
    """Input for reviewing one proposal artifact."""

    proposal_id: str = Field(description="Stable proposal identifier returned by orch_list_proposals.")
    note: str | None = Field(default=None, description="Optional review note to record with the proposal decision.")
    metadata: dict[str, Any] = Field(
        default_factory=dict,
        description="Optional structured metadata to record with the proposal decision.",
    )


class OrchDispatchTaskInput(ToolkitModel):
    """Input for dispatching one specific task to a worker runner."""

    task_id: str = Field(description="Task id to claim and dispatch to the configured worker runner.")
    runner_id: str | None = Field(
        default=None,
        description="Optional runner identifier to record on the claimed task.",
    )


class OrchDispatchNextReadyInput(ToolkitModel):
    """Input for dispatching the next ready task."""

    runner_id: str | None = Field(
        default=None,
        description="Optional runner identifier to record on the claimed task.",
    )


class OrchestratorTaskSpecView(ToolkitModel):
    """Agent-facing view of one task specification."""

    id: str = Field(description="Task identifier.")
    kind: str = Field(description="Machine-readable task kind.")
    title: str = Field(description="Human-readable task title.")
    description: str | None = Field(default=None, description="Optional longer task description.")
    payload: dict[str, Any] = Field(description="Structured task payload data.")
    tags: list[str] = Field(description="Tags associated with the task.")
    priority: int = Field(description="Relative task priority used for scheduler ordering.")
    depends_on: list[str] = Field(description="Direct dependency task ids for the task.")
    max_attempts: int | None = Field(default=None, description="Optional maximum number of allowed attempts.")
    metadata: dict[str, Any] = Field(description="Structured task metadata.")


class OrchestratorTaskAttemptView(ToolkitModel):
    """Agent-facing view of one task attempt."""

    attempt: int = Field(description="1-based attempt number.")
    status: TaskAttemptStatus = Field(description="Lifecycle status of this attempt.")
    started_at: datetime = Field(description="Timestamp when this attempt started.")
    finished_at: datetime | None = Field(default=None, description="Timestamp when this attempt finished, if any.")
    runner_id: str | None = Field(default=None, description="Runner identifier recorded for this attempt, if any.")
    summary: str | None = Field(default=None, description="Optional short summary recorded for this attempt.")
    error_message: str | None = Field(default=None, description="Optional error message recorded for this attempt.")
    metadata: dict[str, Any] = Field(default_factory=dict, description="Structured metadata attached to this attempt.")


class OrchestratorTaskArtifactView(ToolkitModel):
    """Agent-facing view of one task artifact."""

    kind: str = Field(description="Machine-readable artifact kind.")
    label: str | None = Field(default=None, description="Optional short human-readable artifact label.")
    value: Any = Field(description="Artifact payload value.")
    created_at: datetime = Field(description="Timestamp when the artifact was created.")
    metadata: dict[str, Any] = Field(default_factory=dict, description="Structured metadata attached to the artifact.")


class OrchestratorTaskSummaryView(ToolkitModel):
    """Lightweight orchestrator-facing summary of a task."""

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


class OrchestratorTaskDetailView(OrchestratorTaskSummaryView):
    """Richer orchestrator-facing detail view of a task."""

    description: str | None = Field(default=None, description="Optional longer description of the task.")
    payload: dict[str, Any] = Field(description="Structured task payload data.")
    tags: list[str] = Field(description="Tags associated with the task.")
    metadata: dict[str, Any] = Field(description="Structured task metadata.")
    claimed_by: str | None = Field(default=None, description="Runner currently claiming the task, if any.")
    created_at: datetime = Field(description="Timestamp when the task record was created.")
    updated_at: datetime = Field(description="Timestamp when the task record was last updated.")
    started_at: datetime | None = Field(default=None, description="Timestamp when the current or last run started, if any.")
    finished_at: datetime | None = Field(default=None, description="Timestamp when the task reached its current terminal state, if any.")
    dependencies: list[OrchestratorTaskSummaryView] = Field(description="Direct dependency task summaries.")
    attempts: list[OrchestratorTaskAttemptView] = Field(description="Recorded attempt history for the task.")
    artifacts: list[OrchestratorTaskArtifactView] = Field(description="Artifacts attached to the task.")


class OrchestratorTaskListView(ToolkitModel):
    """Ordered list of task summaries."""

    total_tasks: int = Field(description="Total number of tasks in the underlying list before any limit is applied.")
    tasks_returned: int = Field(description="Number of task summaries returned in this payload.")
    tasks: list[OrchestratorTaskSummaryView] = Field(description="Ordered task summaries.")


class OrchestratorTaskTableView(OrchestratorTaskListView):
    """Ordered run-wide table view of tasks."""


class OrchestratorRunSummaryView(ToolkitModel):
    """Run-wide summary view for the orchestrator toolkit."""

    run_id: str = Field(description="Task-run identifier.")
    total_tasks: int = Field(description="Total number of tasks in the run.")
    tasks_returned: int = Field(description="Number of task summaries included in this payload.")
    counts_by_lifecycle_status: dict[str, int] = Field(
        description="Counts of tasks grouped by stored lifecycle status.",
    )
    counts_by_scheduler_status: dict[str, int] = Field(
        description="Counts of tasks grouped by derived scheduler status.",
    )
    metadata: dict[str, Any] = Field(description="Run-level metadata stored with the task run.")
    tasks: list[OrchestratorTaskSummaryView] = Field(description="Ordered task summaries for the run.")


class OrchestratorGraphValidationView(ToolkitModel):
    """Success payload returned when explicit graph validation passes."""

    run_id: str = Field(description="Task-run identifier.")
    valid: Literal[True] = True
    total_tasks: int = Field(description="Total number of tasks currently in the run.")
    total_dependencies: int = Field(description="Total number of dependency edges across all tasks.")


class OrchestratorProposalView(ToolkitModel):
    """Agent-facing view of one recorded task proposal batch."""

    proposal_id: str = Field(description="Stable proposal identifier.")
    source_task_id: str = Field(description="Task id that originally recorded the proposal artifact.")
    artifact_index: int = Field(description="1-based artifact position of the proposal on the source task.")
    created_at: datetime = Field(description="Timestamp when the proposal artifact was created.")
    status: TaskProposalStatus = Field(description="Derived review status of the proposal.")
    rationale: str | None = Field(default=None, description="Optional explanation recorded with the proposal.")
    proposal_count: int = Field(description="Number of proposed tasks contained in the batch.")
    proposals: list[OrchestratorTaskSpecView] = Field(description="Validated task specifications proposed in the batch.")
    artifact_metadata: dict[str, Any] = Field(description="Structured metadata attached to the proposal artifact.")
    review_note: str | None = Field(default=None, description="Optional latest review note for the proposal.")
    applied_task_ids: list[str] = Field(description="Task ids created when the proposal was applied, if any.")
    review_metadata: dict[str, Any] = Field(description="Structured metadata attached to the latest review decision.")
    review_created_at: datetime | None = Field(default=None, description="Timestamp when the latest review decision was recorded, if any.")


class OrchestratorProposalListView(ToolkitModel):
    """Ordered list of proposal views."""

    total_proposals: int = Field(description="Total number of proposals in the filtered list before any limit is applied.")
    proposals_returned: int = Field(description="Number of proposal views returned in this payload.")
    proposals: list[OrchestratorProposalView] = Field(description="Ordered proposal views.")


class OrchestratorDispatchResultView(ToolkitModel):
    """Result returned after dispatching a task through a worker runner."""

    task: OrchestratorTaskDetailView = Field(description="Final task detail after dispatch completed.")
    execution_status: TaskExecutionStatus = Field(description="Worker-reported execution status.")
    runner_id: str | None = Field(default=None, description="Runner identifier recorded for the dispatched task, if any.")
    summary: str | None = Field(default=None, description="Optional summary returned by the worker execution result.")
    error_message: str | None = Field(default=None, description="Optional error message returned by the worker execution result.")
