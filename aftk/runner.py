from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Sequence

from pydantic import BaseModel, Field
from pydantic_ai.agent import AgentRunResult
from pydantic_ai.messages import ModelRequest, ModelResponse, RetryPromptPart, TextPart, ToolCallPart, ToolReturnPart

from aftk.agents import (
    DEFAULT_INITIALIZER_USER_PROMPT,
    DEFAULT_ORCHESTRATOR_USER_PROMPT,
    DEFAULT_WORKER_USER_PROMPT,
    InitializerService,
    OrchestratorDecision,
    OrchestratorService,
    WorkerOutcome,
    WorkerReport,
    WorkerService,
    build_initializer_toolsets,
    build_orchestrator_toolsets,
    build_worker_toolsets,
)
from aftk.coding.logs import CodingActionRecorder
from aftk.config import FrameworkConfig, FrameworkModel, FrameworkPaths
from aftk.project import ProjectSnapshot, ProjectSnapshotService
from aftk.storage import (
    AgentRole,
    AgentRunRecord,
    LlmCallRecord,
    LlmCallStatus,
    PricingTable,
    ProjectRollupService,
    RunCollection,
    RunLogStore,
    RunStatus,
    RunTelemetrySession,
    ToolCallRecord,
    ToolCallStatus,
    ToolFamily,
)
from aftk.tasks import Task, TaskAttemptStatus, TaskPatch, TaskService, TaskState, TaskStatus
from aftk.tasks.service import TERMINAL_TASK_STATUSES, TaskGraphError, TaskNotReadyError
from aftk.storage.telemetry import UsageSummary, utc_now
from aftk_client import AsyncAftkClient


_PROJECT_TOOL_NAMES = {
    "get_project_snapshot_summary",
    "read_entrypoint",
    "list_source_files",
    "read_source_file",
    "list_lean_files",
}
_CODING_TOOL_NAMES = {
    "list_project_files",
    "search_project_text",
    "read_file",
    "read_file_slice",
    "write_file",
    "replace_in_file",
    "append_to_file",
    "run_command",
    "lake_build",
}


class RunnerDecisionError(RuntimeError):
    """Raised when an orchestrator decision is invalid for the current persistent state."""


class RunnerIterationLimitError(RuntimeError):
    """Raised when the runner exceeds its configured maximum number of orchestrator iterations."""


class RunnerLoopResult(FrameworkModel):
    project_done: bool
    completion_summary: str | None = None
    iterations: int = Field(default=0, ge=0)
    initialization_run_id: str | None = None
    orchestrator_run_ids: list[str] = Field(default_factory=list)
    worker_run_ids: list[str] = Field(default_factory=list)
    final_task_revision: int = Field(default=0, ge=0)


@dataclass(frozen=True, slots=True)
class _LoggedAgentRun:
    run_id: str
    store: RunLogStore
    record: AgentRunRecord
    result: AgentRunResult[Any]


class FrameworkRunner:
    def __init__(
        self,
        config: FrameworkConfig | FrameworkPaths,
        *,
        pricing_table: PricingTable | None = None,
    ) -> None:
        self.config = config if isinstance(config, FrameworkConfig) else FrameworkConfig(paths=config)
        self.snapshot_service = ProjectSnapshotService(self.config)
        self.initializer_service = InitializerService(self.config)
        self.orchestrator_service = OrchestratorService(self.config)
        self.worker_service = WorkerService(self.config)
        self.task_service = TaskService(self.config.paths.tasks_dir)
        self.run_collection = RunCollection(self.config)
        self.rollup_service = ProjectRollupService(self.run_collection, pricing_table=pricing_table)
        self.pricing_table = pricing_table

    async def run(
        self,
        *,
        toolkit_client: AsyncAftkClient | None = None,
        initializer_model: Any | None = None,
        orchestrator_model: Any | None = None,
        worker_model: Any | None = None,
        max_iterations: int = 100,
    ) -> RunnerLoopResult:
        if max_iterations < 1:
            raise ValueError("max_iterations must be at least 1")
        if toolkit_client is None:
            async with AsyncAftkClient(project_root=self.config.project_root) as owned_client:
                return await self._run_with_client(
                    owned_client,
                    initializer_model=initializer_model,
                    orchestrator_model=orchestrator_model,
                    worker_model=worker_model,
                    max_iterations=max_iterations,
                )
        return await self._run_with_client(
            toolkit_client,
            initializer_model=initializer_model,
            orchestrator_model=orchestrator_model,
            worker_model=worker_model,
            max_iterations=max_iterations,
        )

    async def _run_with_client(
        self,
        toolkit_client: AsyncAftkClient,
        *,
        initializer_model: Any | None,
        orchestrator_model: Any | None,
        worker_model: Any | None,
        max_iterations: int,
    ) -> RunnerLoopResult:
        self.run_collection.ensure_layout()
        self.task_service.recover_interrupted_tasks(actor="runner")
        snapshot = self.snapshot_service.build_and_save_snapshot()

        initialization_run_id: str | None = None
        if self._needs_initialization():
            initializer_run = await self._run_initializer(toolkit_client, snapshot=snapshot, model=initializer_model)
            initialization_run_id = initializer_run.run_id
            self.initializer_service.apply_initialization_result(
                initializer_run.result.output,
                actor="initializer",
                snapshot=snapshot,
            )

        orchestrator_run_ids: list[str] = []
        worker_run_ids: list[str] = []
        completion_summary: str | None = None
        last_worker_report: WorkerReport | None = None

        for iteration in range(1, max_iterations + 1):
            snapshot = self.snapshot_service.build_and_save_snapshot()
            task_snapshot = self.task_service.load_state()

            orchestrator_run = await self._run_orchestrator(
                toolkit_client,
                snapshot=snapshot,
                task_snapshot=task_snapshot,
                last_worker_report=last_worker_report,
                model=orchestrator_model,
            )
            orchestrator_run_ids.append(orchestrator_run.run_id)
            decision: OrchestratorDecision = orchestrator_run.result.output
            last_worker_report = None

            preview_state = self._validate_decision(task_snapshot, decision)
            if decision.task_patches:
                self.task_service.apply_patches(decision.task_patches, actor="orchestrator")
            if decision.new_tasks:
                self.task_service.create_tasks(decision.new_tasks, actor="orchestrator")

            if decision.project_done:
                completion_summary = decision.completion_summary
                final_state = self.task_service.load_state()
                return RunnerLoopResult(
                    project_done=True,
                    completion_summary=completion_summary,
                    iterations=iteration,
                    initialization_run_id=initialization_run_id,
                    orchestrator_run_ids=orchestrator_run_ids,
                    worker_run_ids=worker_run_ids,
                    final_task_revision=final_state.revision,
                )

            if decision.selected_task_id is None:
                if preview_state.tasks == task_snapshot.tasks:
                    raise RunnerDecisionError("orchestrator decision made no actionable progress")
                continue

            attempt = self.task_service.claim_task(
                decision.selected_task_id,
                actor="runner",
                worker_kind=self._worker_kind(worker_model),
            )
            try:
                worker_run = await self._run_worker(
                    toolkit_client,
                    snapshot=snapshot,
                    task_brief=decision.worker_brief,
                    task_id=decision.selected_task_id,
                    attempt_id=attempt.id,
                    model=worker_model,
                )
            except Exception as exc:
                self.task_service.finish_attempt(
                    attempt.id,
                    actor="runner",
                    status=TaskAttemptStatus.FAILED,
                    summary=str(exc),
                )
                raise

            worker_run_ids.append(worker_run.run_id)
            report: WorkerReport = worker_run.result.output
            self.task_service.finish_attempt(
                attempt.id,
                actor="runner",
                status=_attempt_status_from_report(report),
                summary=report.summary,
                run_id=worker_run.run_id,
                report_path=worker_run.record.artifacts.result_path,
                transcript_path=worker_run.record.artifacts.messages_path,
                llm_call_log_path=worker_run.record.artifacts.llm_call_log_path,
                tool_call_log_path=worker_run.record.artifacts.tool_call_log_path,
                usage_summary=_attempt_usage_summary(worker_run.record.usage_summary),
                cost_summary=None if worker_run.record.cost_summary is None else worker_run.record.cost_summary.model_dump(mode="json"),
            )
            last_worker_report = report

        raise RunnerIterationLimitError(f"runner exceeded max_iterations={max_iterations}")

    async def _run_initializer(
        self,
        toolkit_client: AsyncAftkClient,
        *,
        snapshot: ProjectSnapshot,
        model: Any | None,
    ) -> _LoggedAgentRun:
        toolsets = build_initializer_toolsets(snapshot, toolkit_client)
        return await self._run_logged_agent(
            agent_role=AgentRole.INITIALIZER,
            model_name=_model_name_for_run(model, fallback=self.config.models.initializer),
            invoke=lambda: self.initializer_service.run_initializer(
                toolkit_client,
                model=model,
                snapshot=snapshot,
                user_prompt=DEFAULT_INITIALIZER_USER_PROMPT,
                toolsets=toolsets,
            ),
        )

    async def _run_orchestrator(
        self,
        toolkit_client: AsyncAftkClient,
        *,
        snapshot: ProjectSnapshot,
        task_snapshot: TaskState,
        last_worker_report: WorkerReport | None,
        model: Any | None,
    ) -> _LoggedAgentRun:
        toolsets = build_orchestrator_toolsets(snapshot, toolkit_client)
        return await self._run_logged_agent(
            agent_role=AgentRole.ORCHESTRATOR,
            model_name=_model_name_for_run(model, fallback=self.config.models.orchestrator),
            invoke=lambda: self.orchestrator_service.run_orchestrator(
                toolkit_client,
                task_snapshot=task_snapshot,
                last_worker_report=last_worker_report,
                model=model,
                snapshot=snapshot,
                user_prompt=DEFAULT_ORCHESTRATOR_USER_PROMPT,
                toolsets=toolsets,
            ),
        )

    async def _run_worker(
        self,
        toolkit_client: AsyncAftkClient,
        *,
        snapshot: ProjectSnapshot,
        task_brief,
        task_id: str,
        attempt_id: str,
        model: Any | None,
    ) -> _LoggedAgentRun:
        run_id = self.run_collection.next_run_id()
        recorder = CodingActionRecorder.for_project(self.config, run_id=run_id, task_id=task_id, attempt_id=attempt_id)
        toolsets = build_worker_toolsets(self.config, snapshot, toolkit_client, recorder=recorder)
        return await self._run_logged_agent(
            agent_role=AgentRole.WORKER,
            model_name=_model_name_for_run(model, fallback=self.config.models.worker),
            task_id=task_id,
            attempt_id=attempt_id,
            run_id=run_id,
            invoke=lambda: self.worker_service.run_worker(
                toolkit_client,
                task_brief=task_brief,
                model=model,
                snapshot=snapshot,
                user_prompt=DEFAULT_WORKER_USER_PROMPT,
                recorder=recorder,
                toolsets=toolsets,
            ),
        )

    async def _run_logged_agent(
        self,
        *,
        agent_role: AgentRole,
        model_name: str | None,
        invoke,
        task_id: str | None = None,
        attempt_id: str | None = None,
        run_id: str | None = None,
    ) -> _LoggedAgentRun:
        chosen_run_id = self.run_collection.next_run_id() if run_id is None else run_id
        store = self.run_collection.run_store(chosen_run_id)
        session = RunTelemetrySession(store, pricing_table=self.pricing_table)
        session.start_run(
            agent_role=agent_role,
            model_name=model_name,
            task_id=task_id,
            attempt_id=attempt_id,
        )
        try:
            result: AgentRunResult[Any] = await invoke()
        except Exception as exc:
            record = session.finalize_run(status=RunStatus.FAILED, error_message=str(exc))
            self.rollup_service.rebuild_rollups()
            raise

        session.save_result_payload(result.output)
        session.save_messages_from_result(result)
        llm_calls, tool_calls = _extract_telemetry_records(
            result,
            run_id=chosen_run_id,
            agent_role=agent_role,
            task_id=task_id,
            attempt_id=attempt_id,
        )
        for call in llm_calls:
            session.append_llm_call(call)
        for call in tool_calls:
            session.append_tool_call(call)
        record = session.finalize_run(status=RunStatus.COMPLETED, run_usage=session.usage_from_result(result))
        self.rollup_service.rebuild_rollups()
        return _LoggedAgentRun(run_id=chosen_run_id, store=store, record=record, result=result)

    def _needs_initialization(self) -> bool:
        if self.initializer_service.has_initialization():
            return False
        return not bool(self.task_service.load_state().tasks)

    def _validate_decision(self, state: TaskState, decision: OrchestratorDecision) -> TaskState:
        if not decision.project_done and decision.selected_task_id is None and not decision.new_tasks and not decision.task_patches:
            raise RunnerDecisionError("orchestrator decision produced no completion, task selection, or graph change")
        if decision.selected_task_id is not None and decision.selected_task_id not in state.tasks:
            raise RunnerDecisionError(f"selected task does not exist in current state: {decision.selected_task_id}")

        preview_state = self._preview_decision_state(state, decision)

        if decision.project_done:
            remaining = sorted(task.id for task in preview_state.tasks.values() if task.status not in TERMINAL_TASK_STATUSES)
            if remaining:
                raise RunnerDecisionError(
                    f"project_done is invalid while non-terminal tasks remain: {', '.join(remaining)}"
                )
            return preview_state

        if decision.selected_task_id is not None:
            selected_task = preview_state.tasks[decision.selected_task_id]
            if not self.task_service.is_task_ready(selected_task, preview_state):
                raise RunnerDecisionError(f"selected task is not ready after proposed changes: {decision.selected_task_id}")
        return preview_state

    def _preview_decision_state(self, state: TaskState, decision: OrchestratorDecision) -> TaskState:
        timestamp = utc_now()
        tasks = dict(state.tasks)

        for patch in decision.task_patches:
            if patch.new_status is TaskStatus.IN_PROGRESS:
                raise RunnerDecisionError("orchestrator patches cannot set tasks to in_progress; use task claiming instead")
            current = tasks.get(patch.task_id)
            if current is None:
                raise RunnerDecisionError(f"patch references unknown task id: {patch.task_id}")
            tasks[patch.task_id] = self.task_service._apply_single_patch(current, patch, actor="orchestrator", now=timestamp)

        existing_ids = list(tasks.keys())
        for draft in decision.new_tasks:
            task_id = self.task_service._next_task_id(existing_ids)
            existing_ids.append(task_id)
            tasks[task_id] = Task(
                id=task_id,
                title=draft.title,
                description=draft.description,
                kind=draft.kind,
                status=TaskStatus.BLOCKED if draft.blockers else TaskStatus.PLANNED,
                priority=draft.priority,
                acceptance_criteria=list(draft.acceptance_criteria),
                depends_on=list(draft.depends_on),
                blockers=list(draft.blockers),
                scope=list(draft.scope),
                context_summary=draft.context_summary,
                notes=[],
                created_by="orchestrator",
                updated_by="orchestrator",
                current_attempt_id=None,
                attempt_count=0,
                created_at=timestamp,
                updated_at=timestamp,
            )

        try:
            normalized_tasks, _ = self.task_service._normalize_tasks(tasks, actor="orchestrator", now=timestamp)
            candidate = self.task_service._candidate_state(state, normalized_tasks)
            self.task_service.validate_state(candidate)
        except (TaskGraphError, ValueError) as exc:
            raise RunnerDecisionError(f"orchestrator decision failed task-state validation: {exc}") from exc
        return candidate

    def _worker_kind(self, model: Any | None) -> str:
        if isinstance(model, str) and model:
            return model
        return self.config.models.worker or "worker"



def _attempt_status_from_report(report: WorkerReport) -> TaskAttemptStatus:
    if report.outcome is WorkerOutcome.COMPLETED:
        return TaskAttemptStatus.COMPLETED
    if report.outcome is WorkerOutcome.PARTIAL:
        return TaskAttemptStatus.PARTIAL
    if report.outcome is WorkerOutcome.BLOCKED:
        return TaskAttemptStatus.BLOCKED
    return TaskAttemptStatus.FAILED



def _model_name_for_run(model: Any | None, *, fallback: str | None) -> str | None:
    if model is None:
        return fallback
    if isinstance(model, str):
        return model
    model_name = getattr(model, "model_name", None)
    if isinstance(model_name, str) and model_name:
        return model_name
    return fallback



def _attempt_usage_summary(usage: UsageSummary | None) -> dict[str, str | int | float | bool | None] | None:
    if usage is None:
        return None
    payload: dict[str, str | int | float | bool | None] = {
        "requests": usage.requests,
        "tool_calls": usage.tool_calls,
        "input_tokens": usage.input_tokens,
        "cache_write_tokens": usage.cache_write_tokens,
        "cache_read_tokens": usage.cache_read_tokens,
        "output_tokens": usage.output_tokens,
        "input_audio_tokens": usage.input_audio_tokens,
        "cache_audio_read_tokens": usage.cache_audio_read_tokens,
        "output_audio_tokens": usage.output_audio_tokens,
        "total_tokens": usage.total_tokens,
    }
    if usage.details:
        payload["details"] = _truncate(str(dict(usage.details)), limit=200)
    return payload



def _extract_telemetry_records(
    result: AgentRunResult[Any],
    *,
    run_id: str,
    agent_role: AgentRole,
    task_id: str | None,
    attempt_id: str | None,
) -> tuple[list[LlmCallRecord], list[ToolCallRecord]]:
    messages = result.new_messages()
    llm_calls = _extract_llm_calls(messages, run_id=run_id, agent_role=agent_role, task_id=task_id, attempt_id=attempt_id)
    tool_calls = _extract_tool_calls(messages, run_id=run_id, agent_role=agent_role, task_id=task_id, attempt_id=attempt_id)
    return llm_calls, tool_calls



def _extract_llm_calls(
    messages: Sequence[ModelRequest | ModelResponse],
    *,
    run_id: str,
    agent_role: AgentRole,
    task_id: str | None,
    attempt_id: str | None,
) -> list[LlmCallRecord]:
    calls: list[LlmCallRecord] = []
    last_request: ModelRequest | None = None
    index = 0
    for message in messages:
        if isinstance(message, ModelRequest):
            last_request = message
            continue
        index += 1
        started_at = message.timestamp if last_request is None or last_request.timestamp is None else last_request.timestamp
        finished_at = message.timestamp
        calls.append(
            LlmCallRecord(
                index=index,
                run_id=run_id,
                agent_role=agent_role.value,
                task_id=task_id,
                attempt_id=attempt_id,
                model_name=message.model_name,
                started_at=started_at,
                finished_at=finished_at,
                duration_seconds=max((finished_at - started_at).total_seconds(), 0.0),
                status=LlmCallStatus.SUCCEEDED,
                usage=UsageSummary.from_value(message.usage),
                request_summary=None if last_request is None else _summarize_request(last_request),
                response_summary=_summarize_response(message),
            )
        )
    return calls



def _extract_tool_calls(
    messages: Sequence[ModelRequest | ModelResponse],
    *,
    run_id: str,
    agent_role: AgentRole,
    task_id: str | None,
    attempt_id: str | None,
) -> list[ToolCallRecord]:
    pending: dict[str, tuple[int, ToolCallPart, datetime]] = {}
    tool_calls: list[ToolCallRecord] = []
    next_index = 1

    for message in messages:
        if isinstance(message, ModelResponse):
            for part in message.parts:
                if isinstance(part, ToolCallPart):
                    pending[part.tool_call_id] = (next_index, part, message.timestamp)
                    next_index += 1
            continue

        for part in message.parts:
            if isinstance(part, ToolReturnPart):
                entry = pending.pop(part.tool_call_id, None)
                if entry is None:
                    continue
                index, call_part, started_at = entry
                tool_calls.append(
                    ToolCallRecord(
                        index=index,
                        run_id=run_id,
                        agent_role=agent_role.value,
                        task_id=task_id,
                        attempt_id=attempt_id,
                        tool_name=call_part.tool_name,
                        tool_family=_tool_family(call_part.tool_name),
                        started_at=started_at,
                        finished_at=part.timestamp,
                        duration_seconds=max((part.timestamp - started_at).total_seconds(), 0.0),
                        status=ToolCallStatus.SUCCEEDED if part.outcome == "success" else ToolCallStatus.FAILED,
                        input_summary=_summarize_tool_args(call_part.args),
                        output_summary=_summarize_tool_output(part.content, outcome=part.outcome),
                        error_message=None if part.outcome == "success" else _truncate(str(part.content)),
                    )
                )
            elif isinstance(part, RetryPromptPart) and part.tool_name is not None:
                entry = pending.pop(part.tool_call_id, None)
                if entry is None:
                    continue
                index, call_part, started_at = entry
                tool_calls.append(
                    ToolCallRecord(
                        index=index,
                        run_id=run_id,
                        agent_role=agent_role.value,
                        task_id=task_id,
                        attempt_id=attempt_id,
                        tool_name=call_part.tool_name,
                        tool_family=_tool_family(call_part.tool_name),
                        started_at=started_at,
                        finished_at=part.timestamp,
                        duration_seconds=max((part.timestamp - started_at).total_seconds(), 0.0),
                        status=ToolCallStatus.FAILED,
                        input_summary=_summarize_tool_args(call_part.args),
                        output_summary={"outcome": "retry"},
                        error_message=_truncate(part.model_response()),
                    )
                )

    for tool_call_id, (index, part, started_at) in pending.items():
        tool_calls.append(
            ToolCallRecord(
                index=index,
                run_id=run_id,
                agent_role=agent_role.value,
                task_id=task_id,
                attempt_id=attempt_id,
                tool_name=part.tool_name,
                tool_family=_tool_family(part.tool_name),
                started_at=started_at,
                finished_at=started_at,
                duration_seconds=0.0,
                status=ToolCallStatus.FAILED,
                input_summary=_summarize_tool_args(part.args),
                output_summary={"outcome": "missing_return"},
                error_message=f"tool call {tool_call_id} did not produce a return part",
            )
        )

    return sorted(tool_calls, key=lambda call: call.index)



def _tool_family(tool_name: str) -> ToolFamily:
    if tool_name in _PROJECT_TOOL_NAMES:
        return ToolFamily.PROJECT
    if tool_name in _CODING_TOOL_NAMES:
        return ToolFamily.CODING
    return ToolFamily.TOOLKIT



def _summarize_request(message: ModelRequest) -> str:
    parts: list[str] = []
    if message.instructions:
        parts.append(f"instructions={_truncate(message.instructions, limit=120)}")
    for part in message.parts:
        if isinstance(part, ToolReturnPart):
            parts.append(f"tool_return:{part.tool_name}[{part.outcome}]")
        elif isinstance(part, RetryPromptPart):
            label = part.tool_name or "output"
            parts.append(f"retry:{label}")
        else:
            content = getattr(part, "content", None)
            if isinstance(content, str):
                parts.append(_truncate(content, limit=120))
            elif content is not None:
                parts.append(type(content).__name__)
            else:
                parts.append(type(part).__name__)
    return " | ".join(parts)



def _summarize_response(message: ModelResponse) -> str:
    parts: list[str] = []
    for part in message.parts:
        if isinstance(part, ToolCallPart):
            parts.append(f"tool_call:{part.tool_name}")
        elif isinstance(part, TextPart):
            parts.append(_truncate(part.content, limit=120))
        else:
            parts.append(type(part).__name__)
    return " | ".join(parts)



def _summarize_tool_args(args: Any) -> dict[str, Any]:
    if isinstance(args, dict):
        return {str(key): _compact_value(value) for key, value in list(args.items())[:20]}
    return {"args": _truncate(str(args), limit=200)}



def _summarize_tool_output(content: Any, *, outcome: str) -> dict[str, Any]:
    return {
        "outcome": outcome,
        "preview": _compact_value(content),
    }



def _compact_value(value: Any) -> Any:
    if isinstance(value, BaseModel):
        return _compact_value(value.model_dump(mode="json"))
    if value is None or isinstance(value, (str, int, float, bool)):
        return _truncate(value, limit=200) if isinstance(value, str) else value
    if isinstance(value, dict):
        return {str(key): _compact_value(item) for key, item in list(value.items())[:10]}
    if isinstance(value, (list, tuple)):
        preview = [_compact_value(item) for item in list(value)[:10]]
        if len(value) > 10:
            preview.append(f"... (+{len(value) - 10} more)")
        return preview
    return _truncate(str(value), limit=200)



def _truncate(value: str, *, limit: int = 160) -> str:
    if len(value) <= limit:
        return value
    return f"{value[: limit - 3]}..."


__all__ = [
    "FrameworkRunner",
    "RunnerDecisionError",
    "RunnerIterationLimitError",
    "RunnerLoopResult",
]
