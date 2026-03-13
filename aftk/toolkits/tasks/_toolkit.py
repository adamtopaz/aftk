from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
from typing import Any, Literal

from pydantic import BaseModel
from pydantic_ai.toolsets import CombinedToolset, FunctionToolset, WrapperToolset

from aftk.tasks import TaskArtifact, TaskLifecycleStatus, TaskManager, TaskRecord, TaskSchedulerStatus
from aftk.tasks.proposals import TASK_PROPOSAL_ARTIFACT_KIND, TaskProposalBatch

from .errors import TaskToolkitExecutionError, failure_from_exception
from .models import (
    TaskArtifactInput,
    TaskArtifactView,
    TaskAttemptView,
    TaskDetailView,
    TaskIdInput,
    TaskListInput,
    TaskListView,
    TaskNoteInput,
    TaskProposalInput,
    TaskSpecInput,
    TaskSummaryView,
    TaskRunSummaryView,
    TaskToolFailure,
    TaskToolSuccess,
)

TaskToolkitMode = Literal["executor", "planner"]


class TaskToolkit(WrapperToolset[Any]):
    """Pydantic AI toolset exposing worker-safe task operations."""

    def __init__(
        self,
        manager: TaskManager,
        *,
        current_task_id: str | None = None,
        mode: TaskToolkitMode = "executor",
        read_only: bool = False,
        advanced: bool = False,
        id: str | None = None,
    ) -> None:
        self._manager = manager
        self._current_task_id = current_task_id
        self._mode: TaskToolkitMode = mode
        self._read_only = read_only
        self._advanced = advanced
        self._id = id
        self.wrapped = self._build_wrapped_toolset()

    @property
    def id(self) -> str | None:
        return self._id

    async def call_tool(self, name: str, tool_args: dict[str, Any], ctx: Any, tool: Any) -> Any:
        try:
            result = await self.wrapped.call_tool(name, tool_args, ctx, tool)
        except Exception as exc:
            return failure_from_exception(name, exc)

        if isinstance(result, (TaskToolSuccess, TaskToolFailure)):
            return result
        return TaskToolSuccess(tool=name, data=self._normalize_result(result))

    def apply(self, visitor: Callable[[Any], None]) -> None:
        self.wrapped.apply(visitor)

    def visit_and_replace(self, visitor: Callable[[Any], Any]) -> Any:
        clone = self.__class__(
            self._manager,
            current_task_id=self._current_task_id,
            mode=self._mode,
            read_only=self._read_only,
            advanced=self._advanced,
            id=self._id,
        )
        clone.wrapped = self.wrapped.visit_and_replace(visitor)
        return clone

    def _build_wrapped_toolset(self) -> CombinedToolset[Any]:
        toolsets: list[FunctionToolset[Any]] = [self._build_read_toolset()]
        if not self._read_only:
            toolsets.append(self._build_write_toolset())
        return CombinedToolset(toolsets=toolsets)

    def _build_read_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="task_run", suffix="read")
        self._register(toolset, self._task_current, name="task_current", mutates=False, advanced=False)
        self._register(toolset, self._task_get, name="task_get", mutates=False, advanced=False)
        self._register(toolset, self._task_run_summary, name="task_run_summary", mutates=False, advanced=False)
        self._register(toolset, self._task_list_ready, name="task_list_ready", mutates=False, advanced=False)
        self._register(toolset, self._task_list_blocked, name="task_list_blocked", mutates=False, advanced=False)
        return toolset

    def _build_write_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="task_run", suffix="write")
        self._register(toolset, self._task_add_note, name="task_add_note", mutates=True, advanced=False)
        self._register(toolset, self._task_add_artifact, name="task_add_artifact", mutates=True, advanced=False)
        self._register(toolset, self._task_propose_tasks, name="task_propose_tasks", mutates=True, advanced=False)
        return toolset

    def _new_function_toolset(self, *, layer: str, suffix: str) -> FunctionToolset[Any]:
        return FunctionToolset(
            docstring_format="google",
            require_parameter_descriptions=True,
            sequential=True,
            metadata={"source": "tasks", "layer": layer},
            id=self._toolset_id(suffix),
        )

    def _register(
        self,
        toolset: FunctionToolset[Any],
        func: Callable[..., Any],
        *,
        name: str,
        mutates: bool,
        advanced: bool,
    ) -> None:
        toolset.add_function(
            func,
            name=name,
            metadata={"mutates": mutates, "advanced": advanced, "mode": self._mode},
        )

    def _toolset_id(self, suffix: str) -> str | None:
        if self._id is None:
            return None
        return f"{self._id}:{suffix}"

    def _summary_view(self, task: TaskRecord) -> TaskSummaryView:
        return TaskSummaryView(
            id=task.id,
            kind=task.kind,
            title=task.title,
            lifecycle_status=task.status,
            scheduler_status=self._manager.scheduler_status(task.id),
            priority=task.priority,
            depends_on=list(task.depends_on),
            result_summary=task.result_summary,
            last_error=task.last_error,
            attempt_count=len(task.attempts),
            max_attempts=task.max_attempts,
        )

    def _detail_view(self, task: TaskRecord) -> TaskDetailView:
        dependencies = [self._summary_view(dep) for dep in self._manager.dependency_tasks(task.id)]
        attempts = [
            TaskAttemptView(
                attempt=attempt.attempt,
                status=attempt.status,
                started_at=attempt.started_at,
                finished_at=attempt.finished_at,
                runner_id=attempt.runner_id,
                summary=attempt.summary,
                error_message=attempt.error_message,
                metadata=dict(attempt.metadata),
            )
            for attempt in task.attempts
        ]
        artifacts = [
            TaskArtifactView(
                kind=artifact.kind,
                label=artifact.label,
                value=artifact.value,
                created_at=artifact.created_at,
                metadata=dict(artifact.metadata),
            )
            for artifact in task.artifacts
        ]
        summary = self._summary_view(task)
        return TaskDetailView(
            **summary.model_dump(),
            description=task.description,
            payload=dict(task.payload),
            tags=list(task.tags),
            metadata=dict(task.metadata),
            claimed_by=task.claimed_by,
            created_at=task.created_at,
            updated_at=task.updated_at,
            started_at=task.started_at,
            finished_at=task.finished_at,
            dependencies=dependencies,
            attempts=attempts,
            artifacts=artifacts,
        )

    def _list_view(self, tasks: Sequence[TaskRecord], *, limit: int | None = None) -> TaskListView:
        selected = list(tasks[:limit] if limit is not None else tasks)
        return TaskListView(
            total_tasks=len(tasks),
            tasks_returned=len(selected),
            tasks=[self._summary_view(task) for task in selected],
        )

    def _run_summary_view(self, *, limit: int | None = None) -> TaskRunSummaryView:
        ordered_tasks = self._manager.list_tasks()
        lifecycle_counts = {status.value: 0 for status in TaskLifecycleStatus}
        scheduler_counts = {status.value: 0 for status in TaskSchedulerStatus}
        for task in ordered_tasks:
            lifecycle_counts[task.status.value] += 1
            scheduler_counts[self._manager.scheduler_status(task.id).value] += 1
        selected = list(ordered_tasks[:limit] if limit is not None else ordered_tasks)
        return TaskRunSummaryView(
            run_id=self._manager.run_id,
            current_task_id=self._current_task_id,
            total_tasks=len(ordered_tasks),
            tasks_returned=len(selected),
            counts_by_lifecycle_status=lifecycle_counts,
            counts_by_scheduler_status=scheduler_counts,
            metadata=dict(self._manager.state.metadata),
            tasks=[self._summary_view(task) for task in selected],
        )

    def _current_task(self) -> TaskRecord:
        task_id = self._current_task_id
        if task_id is None:
            raise TaskToolkitExecutionError(
                kind="no_current_task",
                message="This task toolkit instance is not bound to a current task.",
                retryable=True,
                suggested_action="bind_current_task",
                details={"mode": self._mode, "current_task_id": None},
            )
        return self._manager.get_task(task_id)

    def _resolve_target_task_id(self, task_id: str | None) -> str:
        if self._mode == "executor":
            if self._current_task_id is None:
                raise TaskToolkitExecutionError(
                    kind="no_current_task",
                    message="Executor task tools require a current bound task for writes.",
                    retryable=True,
                    suggested_action="bind_current_task",
                    details={"mode": self._mode, "current_task_id": None, "task_id": task_id},
                )
            if task_id is None:
                return self._current_task_id
            if task_id != self._current_task_id:
                raise TaskToolkitExecutionError(
                    kind="cross_task_write_forbidden",
                    message=(
                        f"Executor task tools may only mutate the current task {self._current_task_id!r}, "
                        f"not {task_id!r}."
                    ),
                    retryable=True,
                    suggested_action="write_current_task_only",
                    details={
                        "mode": self._mode,
                        "current_task_id": self._current_task_id,
                        "task_id": task_id,
                    },
                )
            return task_id

        if task_id is not None:
            return task_id
        if self._current_task_id is not None:
            return self._current_task_id
        raise TaskToolkitExecutionError(
            kind="no_current_task",
            message="No task id was provided and this toolkit instance is not bound to a current task.",
            retryable=True,
            suggested_action="provide_task_id",
            details={"mode": self._mode, "current_task_id": None},
        )

    def _validated_proposals(self, proposals: Sequence[TaskSpecInput]) -> list[TaskSpecInput]:
        seen: set[str] = set()
        normalized: list[TaskSpecInput] = []
        existing_ids = set(self._manager.state.tasks)
        for proposal in proposals:
            spec = proposal.to_task_spec()
            if spec.id in seen:
                raise TaskToolkitExecutionError(
                    kind="invalid_payload",
                    message=f"duplicate proposed task id in batch: {spec.id!r}",
                    retryable=True,
                    suggested_action="deduplicate_proposals",
                    details={"task_id": spec.id},
                )
            if spec.id in existing_ids:
                raise TaskToolkitExecutionError(
                    kind="task_conflict",
                    message=f"proposed task {spec.id!r} already exists in the run",
                    retryable=True,
                    suggested_action="choose_different_task_id",
                    details={"task_id": spec.id},
                )
            seen.add(spec.id)
            normalized.append(TaskSpecInput.model_validate(spec.model_dump()))
        return normalized

    @classmethod
    def _normalize_result(cls, result: Any) -> Any:
        if isinstance(result, BaseModel):
            return result.model_dump(mode="json", by_alias=True)
        if isinstance(result, Mapping):
            return {key: cls._normalize_result(value) for key, value in result.items()}
        if isinstance(result, tuple):
            return [cls._normalize_result(item) for item in result]
        if isinstance(result, list):
            return [cls._normalize_result(item) for item in result]
        return result

    async def _task_current(self) -> TaskDetailView:
        """Return the current bound task.

        Returns the current task with derived scheduler status, dependency summaries,
        attempts, and artifacts.
        """

        return self._detail_view(self._current_task())

    async def _task_get(self, params: TaskIdInput) -> TaskDetailView:
        """Return one task by id.

        Args:
            params: Input parameters describing the task id to inspect.
        """

        return self._detail_view(self._manager.get_task(params.task_id))

    async def _task_run_summary(self, params: TaskListInput) -> TaskRunSummaryView:
        """Return a run-wide task summary.

        Args:
            params: Input parameters describing optional output limits for included task summaries.
        """

        return self._run_summary_view(limit=params.limit)

    async def _task_list_ready(self, params: TaskListInput) -> TaskListView:
        """Return ready-task summaries.

        Args:
            params: Input parameters describing optional output limits for ready-task summaries.
        """

        return self._list_view(self._manager.ready_tasks(), limit=params.limit)

    async def _task_list_blocked(self, params: TaskListInput) -> TaskListView:
        """Return blocked-task summaries.

        Args:
            params: Input parameters describing optional output limits for blocked-task summaries.
        """

        return self._list_view(self._manager.blocked_tasks(), limit=params.limit)

    async def _task_add_note(self, params: TaskNoteInput) -> TaskDetailView:
        """Attach a note artifact to a task.

        Args:
            params: Input parameters describing the target task, note text, and optional metadata.
        """

        task_id = self._resolve_target_task_id(params.task_id)
        updated = self._manager.attach_note(task_id, params.text, metadata=params.metadata)
        return self._detail_view(updated)

    async def _task_add_artifact(self, params: TaskArtifactInput) -> TaskDetailView:
        """Attach a structured artifact to a task.

        Args:
            params: Input parameters describing the target task and artifact payload.
        """

        task_id = self._resolve_target_task_id(params.task_id)
        updated = self._manager.attach_artifact(
            task_id,
            TaskArtifact(
                kind=params.kind,
                label=params.label,
                value=params.value,
                metadata=dict(params.metadata),
            ),
        )
        return self._detail_view(updated)

    async def _task_propose_tasks(self, params: TaskProposalInput) -> TaskDetailView:
        """Record proposed follow-up tasks as an artifact without mutating the graph.

        Args:
            params: Input parameters describing the target task and validated proposed task specifications.
        """

        task_id = self._resolve_target_task_id(params.task_id)
        proposals = self._validated_proposals(params.proposals)
        proposal_batch = TaskProposalBatch(
            source_task_id=task_id,
            rationale=params.rationale,
            proposals=[proposal.to_task_spec() for proposal in proposals],
        )
        metadata = dict(params.metadata)
        metadata.setdefault("source_task_id", task_id)
        metadata.setdefault("proposal_count", len(proposals))
        updated = self._manager.attach_artifact(
            task_id,
            TaskArtifact(
                kind=TASK_PROPOSAL_ARTIFACT_KIND,
                value=proposal_batch.model_dump(mode="json", by_alias=True),
                metadata=metadata,
            ),
        )
        return self._detail_view(updated)
