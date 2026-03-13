from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
from typing import Any

from pydantic import BaseModel
from pydantic_ai.toolsets import CombinedToolset, FunctionToolset, WrapperToolset

from aftk.tasks import (
    TaskArtifact,
    TaskExecutionStatus,
    TaskLifecycleStatus,
    TaskManager,
    TaskRecord,
    TaskSchedulerStatus,
)
from aftk.tasks.proposals import (
    TASK_PROPOSAL_REVIEW_ARTIFACT_KIND,
    TaskProposalDecision,
    TaskProposalRecord,
    TaskProposalReview,
    TaskProposalStatus,
    collect_task_proposals,
    get_task_proposal,
)
from aftk.tasks.workers import TaskWorkerRunner

from .errors import OrchestratorToolkitExecutionError, failure_from_exception
from .models import (
    OrchAddDependencyInput,
    OrchAddTaskInput,
    OrchAddTasksInput,
    OrchArtifactSpecInput,
    OrchCancelTaskInput,
    OrchClaimTaskInput,
    OrchCompleteTaskInput,
    OrchDispatchNextReadyInput,
    OrchDispatchTaskInput,
    OrchFailTaskInput,
    OrchProposalActionInput,
    OrchProposalIdInput,
    OrchProposalListInput,
    OrchRequeueTaskInput,
    OrchTaskArtifactInput,
    OrchTaskIdInput,
    OrchTaskListInput,
    OrchTaskNoteInput,
    OrchestratorDispatchResultView,
    OrchestratorGraphValidationView,
    OrchestratorProposalListView,
    OrchestratorProposalView,
    OrchestratorRunSummaryView,
    OrchestratorTaskArtifactView,
    OrchestratorTaskAttemptView,
    OrchestratorTaskDetailView,
    OrchestratorTaskListView,
    OrchestratorTaskSpecView,
    OrchestratorTaskSummaryView,
    OrchestratorTaskTableView,
    OrchestratorToolFailure,
    OrchestratorToolSuccess,
)


class OrchestratorToolkit(WrapperToolset[Any]):
    """Pydantic AI toolset exposing global task-run control to orchestrator agents."""

    def __init__(
        self,
        manager: TaskManager,
        *,
        worker_runner: TaskWorkerRunner | None = None,
        read_only: bool = False,
        advanced: bool = False,
        id: str | None = None,
    ) -> None:
        self._manager = manager
        self._worker_runner = worker_runner
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

        if isinstance(result, (OrchestratorToolSuccess, OrchestratorToolFailure)):
            return result
        return OrchestratorToolSuccess(tool=name, data=self._normalize_result(result))

    def apply(self, visitor: Callable[[Any], None]) -> None:
        self.wrapped.apply(visitor)

    def visit_and_replace(self, visitor: Callable[[Any], Any]) -> Any:
        clone = self.__class__(
            self._manager,
            worker_runner=self._worker_runner,
            read_only=self._read_only,
            advanced=self._advanced,
            id=self._id,
        )
        clone.wrapped = self.wrapped.visit_and_replace(visitor)
        return clone

    def _build_wrapped_toolset(self) -> CombinedToolset[Any]:
        toolsets: list[FunctionToolset[Any]] = [
            self._build_read_toolset(),
            self._build_proposal_read_toolset(),
        ]
        if not self._read_only:
            toolsets.append(self._build_control_toolset())
            toolsets.append(self._build_proposal_write_toolset())
            if self._worker_runner is not None:
                toolsets.append(self._build_dispatch_toolset())
        return CombinedToolset(toolsets=toolsets)

    def _build_read_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="task_run", suffix="read")
        self._register(toolset, self._orch_run_summary, name="orch_run_summary", mutates=False, advanced=False)
        self._register(toolset, self._orch_task_table, name="orch_task_table", mutates=False, advanced=False)
        self._register(toolset, self._orch_get_task, name="orch_get_task", mutates=False, advanced=False)
        self._register(toolset, self._orch_list_ready, name="orch_list_ready", mutates=False, advanced=False)
        self._register(toolset, self._orch_list_blocked, name="orch_list_blocked", mutates=False, advanced=False)
        self._register(toolset, self._orch_list_running, name="orch_list_running", mutates=False, advanced=False)
        self._register(toolset, self._orch_list_failed, name="orch_list_failed", mutates=False, advanced=False)
        self._register(toolset, self._orch_list_terminal, name="orch_list_terminal", mutates=False, advanced=False)
        self._register(toolset, self._orch_list_incomplete, name="orch_list_incomplete", mutates=False, advanced=False)
        self._register(toolset, self._orch_validate_graph, name="orch_validate_graph", mutates=False, advanced=False)
        return toolset

    def _build_control_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="task_run", suffix="control")
        self._register(toolset, self._orch_add_task, name="orch_add_task", mutates=True, advanced=False)
        self._register(toolset, self._orch_add_tasks, name="orch_add_tasks", mutates=True, advanced=False)
        self._register(toolset, self._orch_add_dependency, name="orch_add_dependency", mutates=True, advanced=False)
        self._register(toolset, self._orch_attach_note, name="orch_attach_note", mutates=True, advanced=False)
        self._register(toolset, self._orch_attach_artifact, name="orch_attach_artifact", mutates=True, advanced=False)
        self._register(toolset, self._orch_claim_task, name="orch_claim_task", mutates=True, advanced=False)
        self._register(toolset, self._orch_complete_task, name="orch_complete_task", mutates=True, advanced=False)
        self._register(toolset, self._orch_fail_task, name="orch_fail_task", mutates=True, advanced=False)
        self._register(toolset, self._orch_cancel_task, name="orch_cancel_task", mutates=True, advanced=False)
        self._register(toolset, self._orch_requeue_task, name="orch_requeue_task", mutates=True, advanced=False)
        return toolset

    def _build_proposal_read_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="proposal", suffix="proposal-read")
        self._register(toolset, self._orch_list_proposals, name="orch_list_proposals", mutates=False, advanced=False)
        self._register(toolset, self._orch_get_proposal, name="orch_get_proposal", mutates=False, advanced=False)
        return toolset

    def _build_proposal_write_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="proposal", suffix="proposal-write")
        self._register(toolset, self._orch_apply_proposal, name="orch_apply_proposal", mutates=True, advanced=False)
        self._register(toolset, self._orch_reject_proposal, name="orch_reject_proposal", mutates=True, advanced=False)
        return toolset

    def _build_dispatch_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="dispatch", suffix="dispatch")
        self._register(
            toolset,
            self._orch_dispatch_task,
            name="orch_dispatch_task",
            mutates=True,
            advanced=False,
            dispatch=True,
        )
        self._register(
            toolset,
            self._orch_dispatch_next_ready,
            name="orch_dispatch_next_ready",
            mutates=True,
            advanced=False,
            dispatch=True,
        )
        return toolset

    def _new_function_toolset(self, *, layer: str, suffix: str) -> FunctionToolset[Any]:
        return FunctionToolset(
            docstring_format="google",
            require_parameter_descriptions=True,
            sequential=True,
            metadata={"source": "orchestrator", "layer": layer},
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
        dispatch: bool = False,
    ) -> None:
        toolset.add_function(
            func,
            name=name,
            metadata={
                "mutates": mutates,
                "advanced": advanced,
                "role": "orchestrator",
                "dispatch": dispatch,
            },
        )

    def _toolset_id(self, suffix: str) -> str | None:
        if self._id is None:
            return None
        return f"{self._id}:{suffix}"

    def _task_spec_view(self, task: TaskRecord | Any) -> OrchestratorTaskSpecView:
        return OrchestratorTaskSpecView(
            id=task.id,
            kind=task.kind,
            title=task.title,
            description=task.description,
            payload=dict(task.payload),
            tags=list(task.tags),
            priority=task.priority,
            depends_on=list(task.depends_on),
            max_attempts=task.max_attempts,
            metadata=dict(task.metadata),
        )

    def _summary_view(self, task: TaskRecord) -> OrchestratorTaskSummaryView:
        return OrchestratorTaskSummaryView(
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

    def _detail_view(self, task: TaskRecord) -> OrchestratorTaskDetailView:
        dependencies = [self._summary_view(dep) for dep in self._manager.dependency_tasks(task.id)]
        attempts = [
            OrchestratorTaskAttemptView(
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
            OrchestratorTaskArtifactView(
                kind=artifact.kind,
                label=artifact.label,
                value=artifact.value,
                created_at=artifact.created_at,
                metadata=dict(artifact.metadata),
            )
            for artifact in task.artifacts
        ]
        summary = self._summary_view(task)
        return OrchestratorTaskDetailView(
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

    def _list_view(self, tasks: Sequence[TaskRecord], *, limit: int | None = None) -> OrchestratorTaskListView:
        selected = list(tasks[:limit] if limit is not None else tasks)
        return OrchestratorTaskListView(
            total_tasks=len(tasks),
            tasks_returned=len(selected),
            tasks=[self._summary_view(task) for task in selected],
        )

    def _table_view(self, tasks: Sequence[TaskRecord], *, limit: int | None = None) -> OrchestratorTaskTableView:
        selected = list(tasks[:limit] if limit is not None else tasks)
        return OrchestratorTaskTableView(
            total_tasks=len(tasks),
            tasks_returned=len(selected),
            tasks=[self._summary_view(task) for task in selected],
        )

    def _run_summary_view(self, *, limit: int | None = None) -> OrchestratorRunSummaryView:
        ordered_tasks = self._manager.list_tasks()
        lifecycle_counts = {status.value: 0 for status in TaskLifecycleStatus}
        scheduler_counts = {status.value: 0 for status in TaskSchedulerStatus}
        for task in ordered_tasks:
            lifecycle_counts[task.status.value] += 1
            scheduler_counts[self._manager.scheduler_status(task.id).value] += 1
        selected = list(ordered_tasks[:limit] if limit is not None else ordered_tasks)
        return OrchestratorRunSummaryView(
            run_id=self._manager.run_id,
            total_tasks=len(ordered_tasks),
            tasks_returned=len(selected),
            counts_by_lifecycle_status=lifecycle_counts,
            counts_by_scheduler_status=scheduler_counts,
            metadata=dict(self._manager.state.metadata),
            tasks=[self._summary_view(task) for task in selected],
        )

    def _proposal_view(self, proposal: TaskProposalRecord) -> OrchestratorProposalView:
        review = proposal.review
        return OrchestratorProposalView(
            proposal_id=proposal.proposal_id,
            source_task_id=proposal.source_task_id,
            artifact_index=proposal.artifact_index,
            created_at=proposal.created_at,
            status=proposal.status,
            rationale=proposal.rationale,
            proposal_count=len(proposal.proposals),
            proposals=[self._task_spec_view(task) for task in proposal.proposals],
            artifact_metadata=dict(proposal.artifact_metadata),
            review_note=review.note if review is not None else None,
            applied_task_ids=list(review.applied_task_ids) if review is not None else [],
            review_metadata=dict(review.metadata) if review is not None else {},
            review_created_at=proposal.review_created_at,
        )

    def _proposal_list_view(
        self,
        proposals: Sequence[TaskProposalRecord],
        *,
        limit: int | None = None,
    ) -> OrchestratorProposalListView:
        selected = list(proposals[:limit] if limit is not None else proposals)
        return OrchestratorProposalListView(
            total_proposals=len(proposals),
            proposals_returned=len(selected),
            proposals=[self._proposal_view(proposal) for proposal in selected],
        )

    def _proposal_records(self, *, status: TaskProposalStatus | None) -> list[TaskProposalRecord]:
        proposals = collect_task_proposals(self._manager.list_tasks())
        if status is None:
            return proposals
        return [proposal for proposal in proposals if proposal.status == status]

    def _proposal_record(self, proposal_id: str) -> TaskProposalRecord:
        proposal = get_task_proposal(self._manager.list_tasks(), proposal_id)
        if proposal is None:
            raise OrchestratorToolkitExecutionError(
                kind="proposal_not_found",
                message=f"Proposal {proposal_id!r} was not found.",
                retryable=True,
                suggested_action="check_proposal_id",
                details={"proposal_id": proposal_id, "run_id": self._manager.run_id},
            )
        return proposal

    def _assert_pending_proposal(self, proposal: TaskProposalRecord) -> None:
        if proposal.status == TaskProposalStatus.pending:
            return
        if proposal.status == TaskProposalStatus.applied:
            message = f"Proposal {proposal.proposal_id!r} was already applied."
        else:
            message = f"Proposal {proposal.proposal_id!r} was already rejected."
        raise OrchestratorToolkitExecutionError(
            kind="proposal_conflict",
            message=message,
            retryable=True,
            suggested_action="inspect_proposal_status",
            details={
                "proposal_id": proposal.proposal_id,
                "status": proposal.status.value,
                "source_task_id": proposal.source_task_id,
            },
        )

    def _artifact_from_spec(self, spec: OrchArtifactSpecInput) -> TaskArtifact:
        return TaskArtifact(
            kind=spec.kind,
            label=spec.label,
            value=spec.value,
            metadata=dict(spec.metadata),
        )

    def _attach_proposal_review(
        self,
        proposal: TaskProposalRecord,
        *,
        decision: TaskProposalDecision,
        note: str | None,
        metadata: dict[str, Any],
        applied_task_ids: Sequence[str] = (),
    ) -> None:
        review = TaskProposalReview(
            proposal_id=proposal.proposal_id,
            source_task_id=proposal.source_task_id,
            decision=decision,
            note=note,
            applied_task_ids=list(applied_task_ids),
            metadata=dict(metadata),
        )
        self._manager.attach_artifact(
            proposal.source_task_id,
            TaskArtifact(
                kind=TASK_PROPOSAL_REVIEW_ARTIFACT_KIND,
                value=review.model_dump(mode="json", by_alias=True),
                metadata={
                    "proposal_id": proposal.proposal_id,
                    "decision": decision.value,
                    "source_task_id": proposal.source_task_id,
                },
            ),
        )

    def _running_tasks(self) -> list[TaskRecord]:
        return [task for task in self._manager.incomplete_tasks() if task.status == TaskLifecycleStatus.running]

    def _failed_tasks(self) -> list[TaskRecord]:
        return [task for task in self._manager.terminal_tasks() if task.status == TaskLifecycleStatus.failed]

    def _require_worker_runner(self) -> TaskWorkerRunner:
        if self._worker_runner is None:
            raise OrchestratorToolkitExecutionError(
                kind="worker_runner_unavailable",
                message="This orchestrator toolkit instance was not configured with a worker runner.",
                retryable=True,
                suggested_action="configure_worker_runner",
                details={"run_id": self._manager.run_id},
            )
        return self._worker_runner

    def _resolved_runner_id(self, explicit_runner_id: str | None) -> str | None:
        if explicit_runner_id is not None:
            return explicit_runner_id
        runner_name = getattr(self._worker_runner, "name", None)
        if isinstance(runner_name, str) and runner_name:
            return runner_name
        return None

    async def _dispatch_task_id(self, task_id: str, *, runner_id: str | None) -> OrchestratorDispatchResultView:
        runner = self._require_worker_runner()
        resolved_runner_id = self._resolved_runner_id(runner_id)
        claimed = self._manager.claim_task(task_id, runner_id=resolved_runner_id)
        try:
            result = await runner.run_task(self._manager, claimed)
        except Exception as exc:
            failed = self._manager.fail_task(task_id, error_message=str(exc) or exc.__class__.__name__)
            raise OrchestratorToolkitExecutionError(
                kind="worker_dispatch_failed",
                message=f"Worker dispatch failed while executing task {task_id!r}.",
                retryable=True,
                suggested_action="inspect_worker_failure",
                details={
                    "task_id": task_id,
                    "runner_id": resolved_runner_id,
                    "task_status": failed.status.value,
                    "error_message": str(exc) or exc.__class__.__name__,
                },
            ) from exc

        if result.status == TaskExecutionStatus.completed:
            final_task = self._manager.complete_task(
                task_id,
                summary=result.summary,
                artifacts=result.artifacts,
                metadata=result.metadata,
            )
        elif result.status == TaskExecutionStatus.failed:
            assert result.error_message is not None
            final_task = self._manager.fail_task(
                task_id,
                error_message=result.error_message,
                summary=result.summary,
                artifacts=result.artifacts,
                metadata=result.metadata,
            )
        else:
            final_task = self._manager.cancel_task(task_id, summary=result.summary, metadata=result.metadata)

        return OrchestratorDispatchResultView(
            task=self._detail_view(final_task),
            execution_status=result.status,
            runner_id=resolved_runner_id,
            summary=result.summary,
            error_message=result.error_message,
        )

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

    async def _orch_run_summary(self, params: OrchTaskListInput) -> OrchestratorRunSummaryView:
        """Return a run-wide task summary.

        Args:
            params: Input parameters describing optional output limits for included task summaries.
        """

        return self._run_summary_view(limit=params.limit)

    async def _orch_task_table(self, params: OrchTaskListInput) -> OrchestratorTaskTableView:
        """Return an ordered table view of tasks in the run.

        Args:
            params: Input parameters describing optional output limits for task summaries.
        """

        return self._table_view(self._manager.list_tasks(), limit=params.limit)

    async def _orch_get_task(self, params: OrchTaskIdInput) -> OrchestratorTaskDetailView:
        """Return one task by id.

        Args:
            params: Input parameters describing the task id to inspect.
        """

        return self._detail_view(self._manager.get_task(params.task_id))

    async def _orch_list_ready(self, params: OrchTaskListInput) -> OrchestratorTaskListView:
        """Return ready-task summaries.

        Args:
            params: Input parameters describing optional output limits for ready-task summaries.
        """

        return self._list_view(self._manager.ready_tasks(), limit=params.limit)

    async def _orch_list_blocked(self, params: OrchTaskListInput) -> OrchestratorTaskListView:
        """Return blocked-task summaries.

        Args:
            params: Input parameters describing optional output limits for blocked-task summaries.
        """

        return self._list_view(self._manager.blocked_tasks(), limit=params.limit)

    async def _orch_list_running(self, params: OrchTaskListInput) -> OrchestratorTaskListView:
        """Return running-task summaries.

        Args:
            params: Input parameters describing optional output limits for running-task summaries.
        """

        return self._list_view(self._running_tasks(), limit=params.limit)

    async def _orch_list_failed(self, params: OrchTaskListInput) -> OrchestratorTaskListView:
        """Return failed-task summaries.

        Args:
            params: Input parameters describing optional output limits for failed-task summaries.
        """

        return self._list_view(self._failed_tasks(), limit=params.limit)

    async def _orch_list_terminal(self, params: OrchTaskListInput) -> OrchestratorTaskListView:
        """Return terminal-task summaries.

        Args:
            params: Input parameters describing optional output limits for terminal-task summaries.
        """

        return self._list_view(self._manager.terminal_tasks(), limit=params.limit)

    async def _orch_list_incomplete(self, params: OrchTaskListInput) -> OrchestratorTaskListView:
        """Return incomplete-task summaries.

        Args:
            params: Input parameters describing optional output limits for incomplete-task summaries.
        """

        return self._list_view(self._manager.incomplete_tasks(), limit=params.limit)

    async def _orch_validate_graph(self) -> OrchestratorGraphValidationView:
        """Re-run task-graph validation and return a success summary."""

        self._manager.validate()
        state = self._manager.state
        return OrchestratorGraphValidationView(
            run_id=state.run_id,
            total_tasks=len(state.tasks),
            total_dependencies=sum(len(task.depends_on) for task in state.tasks.values()),
        )

    async def _orch_add_task(self, params: OrchAddTaskInput) -> OrchestratorTaskDetailView:
        """Add one task to the run.

        Args:
            params: Input parameters describing the validated task specification to add.
        """

        return self._detail_view(self._manager.add_task(params.task.to_task_spec()))

    async def _orch_add_tasks(self, params: OrchAddTasksInput) -> OrchestratorTaskListView:
        """Add several tasks to the run.

        Args:
            params: Input parameters describing the validated task specifications to add.
        """

        added = self._manager.add_tasks(task.to_task_spec() for task in params.tasks)
        return self._list_view(added)

    async def _orch_add_dependency(self, params: OrchAddDependencyInput) -> OrchestratorTaskDetailView:
        """Add one dependency edge between tasks.

        Args:
            params: Input parameters describing the task id and dependency id to connect.
        """

        return self._detail_view(self._manager.add_dependency(params.task_id, params.dependency_id))

    async def _orch_attach_note(self, params: OrchTaskNoteInput) -> OrchestratorTaskDetailView:
        """Attach an orchestrator note to a task.

        Args:
            params: Input parameters describing the target task, note text, and optional metadata.
        """

        return self._detail_view(self._manager.attach_note(params.task_id, params.text, metadata=params.metadata))

    async def _orch_attach_artifact(self, params: OrchTaskArtifactInput) -> OrchestratorTaskDetailView:
        """Attach an orchestrator artifact to a task.

        Args:
            params: Input parameters describing the target task and artifact payload.
        """

        return self._detail_view(
            self._manager.attach_artifact(
                params.task_id,
                TaskArtifact(
                    kind=params.kind,
                    label=params.label,
                    value=params.value,
                    metadata=dict(params.metadata),
                ),
            )
        )

    async def _orch_claim_task(self, params: OrchClaimTaskInput) -> OrchestratorTaskDetailView:
        """Claim a ready task for execution.

        Args:
            params: Input parameters describing the task id and optional runner id to claim.
        """

        return self._detail_view(self._manager.claim_task(params.task_id, runner_id=params.runner_id))

    async def _orch_complete_task(self, params: OrchCompleteTaskInput) -> OrchestratorTaskDetailView:
        """Mark a running task completed.

        Args:
            params: Input parameters describing the running task, optional summary, artifacts, and metadata.
        """

        return self._detail_view(
            self._manager.complete_task(
                params.task_id,
                summary=params.summary,
                artifacts=[self._artifact_from_spec(artifact) for artifact in params.artifacts],
                metadata=params.metadata,
            )
        )

    async def _orch_fail_task(self, params: OrchFailTaskInput) -> OrchestratorTaskDetailView:
        """Mark a running task failed.

        Args:
            params: Input parameters describing the running task, required error message, and optional artifacts.
        """

        return self._detail_view(
            self._manager.fail_task(
                params.task_id,
                error_message=params.error_message,
                summary=params.summary,
                artifacts=[self._artifact_from_spec(artifact) for artifact in params.artifacts],
                metadata=params.metadata,
            )
        )

    async def _orch_cancel_task(self, params: OrchCancelTaskInput) -> OrchestratorTaskDetailView:
        """Cancel a pending or running task.

        Args:
            params: Input parameters describing the task id and optional cancelation metadata.
        """

        return self._detail_view(
            self._manager.cancel_task(
                params.task_id,
                summary=params.summary,
                metadata=params.metadata,
            )
        )

    async def _orch_requeue_task(self, params: OrchRequeueTaskInput) -> OrchestratorTaskDetailView:
        """Requeue a failed task.

        Args:
            params: Input parameters describing the failed task and whether to clear its last error.
        """

        return self._detail_view(self._manager.requeue_task(params.task_id, clear_error=params.clear_error))

    async def _orch_list_proposals(self, params: OrchProposalListInput) -> OrchestratorProposalListView:
        """List proposal artifacts across the run.

        Args:
            params: Input parameters describing the proposal status filter and optional output limit.
        """

        return self._proposal_list_view(self._proposal_records(status=params.status), limit=params.limit)

    async def _orch_get_proposal(self, params: OrchProposalIdInput) -> OrchestratorProposalView:
        """Return one proposal artifact by id.

        Args:
            params: Input parameters describing the proposal identifier to inspect.
        """

        return self._proposal_view(self._proposal_record(params.proposal_id))

    async def _orch_apply_proposal(self, params: OrchProposalActionInput) -> OrchestratorProposalView:
        """Apply a pending proposal artifact to the task graph.

        Args:
            params: Input parameters describing the proposal identifier and optional review note.
        """

        proposal = self._proposal_record(params.proposal_id)
        self._assert_pending_proposal(proposal)
        added = self._manager.add_tasks(task.model_copy(deep=True) for task in proposal.proposals)
        self._attach_proposal_review(
            proposal,
            decision=TaskProposalDecision.applied,
            note=params.note,
            metadata=params.metadata,
            applied_task_ids=[task.id for task in added],
        )
        return self._proposal_view(self._proposal_record(params.proposal_id))

    async def _orch_reject_proposal(self, params: OrchProposalActionInput) -> OrchestratorProposalView:
        """Record that a proposal artifact was reviewed and rejected.

        Args:
            params: Input parameters describing the proposal identifier and optional review note.
        """

        proposal = self._proposal_record(params.proposal_id)
        if proposal.status == TaskProposalStatus.rejected:
            return self._proposal_view(proposal)
        if proposal.status == TaskProposalStatus.applied:
            self._assert_pending_proposal(proposal)
        self._attach_proposal_review(
            proposal,
            decision=TaskProposalDecision.rejected,
            note=params.note,
            metadata=params.metadata,
        )
        return self._proposal_view(self._proposal_record(params.proposal_id))

    async def _orch_dispatch_task(self, params: OrchDispatchTaskInput) -> OrchestratorDispatchResultView:
        """Claim and dispatch one specific task through the configured worker runner.

        Args:
            params: Input parameters describing the task id and optional runner identifier.
        """

        return await self._dispatch_task_id(params.task_id, runner_id=params.runner_id)

    async def _orch_dispatch_next_ready(self, params: OrchDispatchNextReadyInput) -> OrchestratorDispatchResultView:
        """Claim and dispatch the next ready task in scheduler order.

        Args:
            params: Input parameters describing the optional runner identifier to record.
        """

        ready = self._manager.ready_tasks()
        if not ready:
            raise OrchestratorToolkitExecutionError(
                kind="no_ready_tasks",
                message="No ready tasks are available for dispatch.",
                retryable=True,
                suggested_action="inspect_blocked_tasks",
                details={"run_id": self._manager.run_id},
            )
        return await self._dispatch_task_id(ready[0].id, runner_id=params.runner_id)
