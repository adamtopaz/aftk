from __future__ import annotations

from collections import Counter
from collections.abc import Iterable
from pathlib import Path

from pydantic import Field

from aftk.agents.initializer import ProjectInitializationRecord, ProjectInitializationStore
from aftk.coding.logs import CodingActionLogStore
from aftk.config import FrameworkConfig, FrameworkModel, FrameworkPaths
from aftk.project import ProjectSnapshot, ProjectSnapshotStore
from aftk.storage import AgentRunRecord, PricingTable, ProjectRollupService, ProjectRollups, RunCollection
from aftk.storage.telemetry import UsageSummary
from aftk.tasks import TaskAttempt, TaskEvent, TaskService, TaskState, TaskStatus, TaskStore


class TaskStatusCounts(FrameworkModel):
    planned: int = Field(default=0, ge=0)
    ready: int = Field(default=0, ge=0)
    in_progress: int = Field(default=0, ge=0)
    blocked: int = Field(default=0, ge=0)
    completed: int = Field(default=0, ge=0)
    failed: int = Field(default=0, ge=0)
    cancelled: int = Field(default=0, ge=0)

    @property
    def total(self) -> int:
        return (
            self.planned
            + self.ready
            + self.in_progress
            + self.blocked
            + self.completed
            + self.failed
            + self.cancelled
        )

    @classmethod
    def from_tasks(cls, tasks: Iterable[object]) -> TaskStatusCounts:
        counts = Counter(getattr(task, "status").value for task in tasks)
        return cls(
            planned=counts.get(TaskStatus.PLANNED.value, 0),
            ready=counts.get(TaskStatus.READY.value, 0),
            in_progress=counts.get(TaskStatus.IN_PROGRESS.value, 0),
            blocked=counts.get(TaskStatus.BLOCKED.value, 0),
            completed=counts.get(TaskStatus.COMPLETED.value, 0),
            failed=counts.get(TaskStatus.FAILED.value, 0),
            cancelled=counts.get(TaskStatus.CANCELLED.value, 0),
        )


class TaskEventCounts(FrameworkModel):
    task_created: int = Field(default=0, ge=0)
    task_patched: int = Field(default=0, ge=0)
    task_claimed: int = Field(default=0, ge=0)
    attempt_started: int = Field(default=0, ge=0)
    attempt_finished: int = Field(default=0, ge=0)
    task_recovered: int = Field(default=0, ge=0)
    task_deleted: int = Field(default=0, ge=0)

    @property
    def total(self) -> int:
        return (
            self.task_created
            + self.task_patched
            + self.task_claimed
            + self.attempt_started
            + self.attempt_finished
            + self.task_recovered
            + self.task_deleted
        )

    @classmethod
    def from_events(cls, events: Iterable[TaskEvent]) -> TaskEventCounts:
        counts = Counter(event.kind.value for event in events)
        return cls(
            task_created=counts.get("task_created", 0),
            task_patched=counts.get("task_patched", 0),
            task_claimed=counts.get("task_claimed", 0),
            attempt_started=counts.get("attempt_started", 0),
            attempt_finished=counts.get("attempt_finished", 0),
            task_recovered=counts.get("task_recovered", 0),
            task_deleted=counts.get("task_deleted", 0),
        )


class RunInspection(FrameworkModel):
    record: AgentRunRecord
    llm_call_count: int = Field(default=0, ge=0)
    tool_call_count: int = Field(default=0, ge=0)
    coding_action_count: int = Field(default=0, ge=0)


class FrameworkInspectionReport(FrameworkModel):
    project_root: str
    state_dir: str
    snapshot_path: str | None = None
    initialization_path: str | None = None
    task_state_path: str | None = None
    task_events_path: str | None = None
    runs_dir: str
    rollups_path: str | None = None
    snapshot: ProjectSnapshot | None = None
    initialization: ProjectInitializationRecord | None = None
    task_state: TaskState | None = None
    task_counts: TaskStatusCounts | None = None
    event_counts: TaskEventCounts | None = None
    ready_task_ids: list[str] = Field(default_factory=list)
    in_progress_task_ids: list[str] = Field(default_factory=list)
    attempts: list[TaskAttempt] = Field(default_factory=list)
    recent_events: list[TaskEvent] = Field(default_factory=list)
    recent_runs: list[RunInspection] = Field(default_factory=list)
    rollups: ProjectRollups | None = None


class FrameworkInspectionService:
    def __init__(
        self,
        config: FrameworkConfig | FrameworkPaths,
        *,
        pricing_table: PricingTable | None = None,
    ) -> None:
        self.config = config if isinstance(config, FrameworkConfig) else FrameworkConfig(paths=config)
        self.snapshot_store = ProjectSnapshotStore(self.config.paths)
        self.initialization_store = ProjectInitializationStore(self.config.paths)
        self.task_store = TaskStore(self.config.paths.tasks_dir)
        self.task_service = TaskService(self.task_store)
        self.run_collection = RunCollection(self.config)
        self.rollup_service = ProjectRollupService(self.run_collection, pricing_table=pricing_table)

    def build_report(
        self,
        *,
        max_runs: int = 20,
        max_attempts: int = 20,
        max_events: int = 20,
        rebuild_rollups: bool = False,
    ) -> FrameworkInspectionReport:
        if max_runs < 1:
            raise ValueError("max_runs must be at least 1")
        if max_attempts < 1:
            raise ValueError("max_attempts must be at least 1")
        if max_events < 1:
            raise ValueError("max_events must be at least 1")

        snapshot = self._load_snapshot()
        initialization = self._load_initialization()
        task_state = self._load_task_state()
        task_counts = None if task_state is None else TaskStatusCounts.from_tasks(task_state.tasks.values())
        ready_task_ids, in_progress_task_ids = self._task_status_views(task_state)
        attempts = self._load_attempts(max_attempts=max_attempts)
        all_events = self._load_all_events()
        event_counts = None if not self.task_store.events_path.exists() else TaskEventCounts.from_events(all_events)
        recent_events = self._load_recent_events(all_events, max_events=max_events)
        recent_runs = self._load_recent_runs(max_runs=max_runs)
        rollups = self._load_rollups(rebuild_rollups=rebuild_rollups)

        return FrameworkInspectionReport(
            project_root=str(self.config.paths.project_root),
            state_dir=self.config.paths.relative_to_project_root(self.config.paths.state_dir),
            snapshot_path=self._relative_if_exists(self.snapshot_store.snapshot_path),
            initialization_path=self._relative_if_exists(self.initialization_store.record_path),
            task_state_path=self._relative_if_exists(self.task_store.state_path),
            task_events_path=self._relative_if_exists(self.task_store.events_path),
            runs_dir=self.config.paths.relative_to_project_root(self.config.paths.runs_dir),
            rollups_path=self._relative_if_exists(self.run_collection.rollups_path),
            snapshot=snapshot,
            initialization=initialization,
            task_state=task_state,
            task_counts=task_counts,
            event_counts=event_counts,
            ready_task_ids=ready_task_ids,
            in_progress_task_ids=in_progress_task_ids,
            attempts=attempts,
            recent_events=recent_events,
            recent_runs=recent_runs,
            rollups=rollups,
        )

    def render_text_report(
        self,
        report: FrameworkInspectionReport | None = None,
        *,
        max_task_lines: int = 20,
        max_attempt_lines: int = 10,
        max_event_lines: int = 10,
        max_run_lines: int = 10,
        rebuild_rollups: bool = False,
    ) -> str:
        if max_task_lines < 1:
            raise ValueError("max_task_lines must be at least 1")
        if max_attempt_lines < 1:
            raise ValueError("max_attempt_lines must be at least 1")
        if max_event_lines < 1:
            raise ValueError("max_event_lines must be at least 1")
        if max_run_lines < 1:
            raise ValueError("max_run_lines must be at least 1")

        chosen_report = self.build_report(rebuild_rollups=rebuild_rollups) if report is None else report
        lines = [
            "AFTK framework inspection",
            f"Project root: {chosen_report.project_root}",
            f"State dir: {chosen_report.state_dir}",
        ]

        if chosen_report.snapshot is None:
            lines.append("Snapshot: missing")
        else:
            lines.extend(
                [
                    f"Snapshot: {chosen_report.snapshot_path}",
                    f"  entrypoint: {chosen_report.snapshot.entrypoint_path}",
                    f"  lakefile: {chosen_report.snapshot.lakefile_path}",
                    f"  source files: {len(chosen_report.snapshot.source_inventory)}",
                    f"  lean files: {len(chosen_report.snapshot.lean_files)}",
                ]
            )

        if chosen_report.initialization is None:
            lines.append("Initialization: missing")
        else:
            lines.extend(
                [
                    f"Initialization: {chosen_report.initialization_path}",
                    f"  by: {chosen_report.initialization.initialized_by}",
                    f"  initial tasks: {', '.join(chosen_report.initialization.initial_task_ids) or '(none)'}",
                    f"  summary: {_truncate(chosen_report.initialization.result.project_summary, limit=140)}",
                ]
            )

        if chosen_report.task_state is None or chosen_report.task_counts is None:
            lines.append("Tasks: missing")
        else:
            counts = chosen_report.task_counts
            lines.extend(
                [
                    f"Tasks: revision={chosen_report.task_state.revision} total={counts.total} ready={counts.ready} "
                    f"planned={counts.planned} in_progress={counts.in_progress} blocked={counts.blocked} "
                    f"completed={counts.completed} failed={counts.failed} cancelled={counts.cancelled}",
                    f"  ready ids: {', '.join(chosen_report.ready_task_ids) or '(none)'}",
                    f"  in-progress ids: {', '.join(chosen_report.in_progress_task_ids) or '(none)'}",
                    "  task snapshot:",
                ]
            )
            tasks = sorted(chosen_report.task_state.tasks.values(), key=lambda task: task.id)
            for task in tasks[:max_task_lines]:
                scope = ", ".join(artifact.value for artifact in task.scope) or "none"
                lines.append(f"    - {task.id} [{task.status.value}] {task.title} | scope={scope}")
            if len(tasks) > max_task_lines:
                lines.append(f"    - ... (+{len(tasks) - max_task_lines} more tasks)")

        lines.append("Attempts:")
        if not chosen_report.attempts:
            lines.append("  (none)")
        else:
            for attempt in chosen_report.attempts[:max_attempt_lines]:
                lines.append(
                    "  - "
                    f"{attempt.id} [{attempt.status.value}] task={attempt.task_id} run={attempt.run_id or '(none)'} "
                    f"summary={_truncate(attempt.summary or '(none)', limit=120)}"
                )
            if len(chosen_report.attempts) > max_attempt_lines:
                lines.append(f"  - ... (+{len(chosen_report.attempts) - max_attempt_lines} more attempts)")

        lines.append("Recent task events:")
        if not chosen_report.recent_events:
            lines.append("  (none)")
        else:
            if chosen_report.event_counts is not None:
                counts = chosen_report.event_counts
                lines.append(
                    "  counts: "
                    f"created={counts.task_created} patched={counts.task_patched} claimed={counts.task_claimed} "
                    f"attempt_started={counts.attempt_started} attempt_finished={counts.attempt_finished} "
                    f"recovered={counts.task_recovered} deleted={counts.task_deleted}"
                )
            for event in chosen_report.recent_events[:max_event_lines]:
                lines.append(f"  - {_format_task_event(event)}")
            if len(chosen_report.recent_events) > max_event_lines:
                lines.append(f"  - ... (+{len(chosen_report.recent_events) - max_event_lines} more events)")

        lines.append("Recent runs:")
        if not chosen_report.recent_runs:
            lines.append("  (none)")
        else:
            for run in chosen_report.recent_runs[:max_run_lines]:
                usage = _format_usage(run.record.usage_summary)
                total_cost = 0.0 if run.record.cost_summary is None else run.record.cost_summary.total_cost
                task_context: list[str] = []
                if run.record.task_id is not None:
                    task_context.append(f"task={run.record.task_id}")
                if run.record.attempt_id is not None:
                    task_context.append(f"attempt={run.record.attempt_id}")
                context_suffix = "" if not task_context else f" {' '.join(task_context)}"
                lines.append(
                    "  - "
                    f"{run.record.run_id} {run.record.agent_role.value} [{run.record.status.value}]{context_suffix} "
                    f"model={run.record.model_name or '(none)'} llm_calls={run.llm_call_count} "
                    f"tool_calls={run.tool_call_count} coding_actions={run.coding_action_count} "
                    f"cost={total_cost:.6f} usage={usage}"
                )
            if len(chosen_report.recent_runs) > max_run_lines:
                lines.append(f"  - ... (+{len(chosen_report.recent_runs) - max_run_lines} more runs)")

        if chosen_report.rollups is None:
            lines.append("Rollups: missing")
        else:
            lines.extend(
                [
                    f"Rollups: {chosen_report.rollups_path}",
                    f"  project usage: {_format_usage(chosen_report.rollups.project.usage)}",
                    f"  project cost: {chosen_report.rollups.project.total_cost:.6f}",
                ]
            )
            if chosen_report.rollups.by_attempt:
                lines.append("  by attempt:")
                attempt_ids = sorted(chosen_report.rollups.by_attempt, reverse=True)
                for attempt_id in attempt_ids[:max_attempt_lines]:
                    bucket = chosen_report.rollups.by_attempt[attempt_id]
                    lines.append(
                        f"    - {attempt_id}: runs={bucket.run_count} llm_calls={bucket.llm_call_count} "
                        f"tool_calls={bucket.tool_call_count} cost={bucket.total_cost:.6f} usage={_format_usage(bucket.usage)}"
                    )
                if len(attempt_ids) > max_attempt_lines:
                    lines.append(f"    - ... (+{len(attempt_ids) - max_attempt_lines} more attempts)")
            if chosen_report.rollups.by_agent_role:
                lines.append("  by agent role:")
                for role in sorted(chosen_report.rollups.by_agent_role):
                    bucket = chosen_report.rollups.by_agent_role[role]
                    lines.append(
                        f"    - {role}: runs={bucket.run_count} llm_calls={bucket.llm_call_count} "
                        f"tool_calls={bucket.tool_call_count} cost={bucket.total_cost:.6f} usage={_format_usage(bucket.usage)}"
                    )
            if chosen_report.rollups.by_model:
                lines.append("  by model:")
                for model_name in sorted(chosen_report.rollups.by_model):
                    bucket = chosen_report.rollups.by_model[model_name]
                    lines.append(
                        f"    - {model_name}: llm_calls={bucket.llm_call_count} cost={bucket.total_cost:.6f} "
                        f"usage={_format_usage(bucket.usage)}"
                    )

        return "\n".join(lines)

    def render_json_report(
        self,
        report: FrameworkInspectionReport | None = None,
        *,
        indent: int | None = 2,
        rebuild_rollups: bool = False,
    ) -> str:
        chosen_report = self.build_report(rebuild_rollups=rebuild_rollups) if report is None else report
        return chosen_report.model_dump_json(indent=indent)

    def _load_snapshot(self) -> ProjectSnapshot | None:
        if not self.snapshot_store.has_snapshot():
            return None
        return self.snapshot_store.load_snapshot()

    def _load_initialization(self) -> ProjectInitializationRecord | None:
        if not self.initialization_store.has_record():
            return None
        return self.initialization_store.load_record()

    def _load_task_state(self) -> TaskState | None:
        if not self.task_store.has_state():
            return None
        return self.task_store.load_state()

    def _load_attempts(self, *, max_attempts: int) -> list[TaskAttempt]:
        attempts = sorted(
            self.task_store.list_attempts(),
            key=lambda attempt: (attempt.started_at, attempt.id),
            reverse=True,
        )
        return attempts[:max_attempts]

    def _load_all_events(self) -> list[TaskEvent]:
        if not self.task_store.events_path.exists():
            return []
        return self.task_store.load_events()

    def _load_recent_events(self, events: list[TaskEvent], *, max_events: int) -> list[TaskEvent]:
        ordered = sorted(
            events,
            key=lambda event: (
                event.timestamp,
                event.kind.value,
                event.task_id or "",
                event.attempt_id or "",
            ),
            reverse=True,
        )
        return ordered[:max_events]

    def _load_recent_runs(self, *, max_runs: int) -> list[RunInspection]:
        run_ids = self.run_collection.list_run_ids()
        selected = list(reversed(run_ids[-max_runs:]))
        recent_runs: list[RunInspection] = []
        for run_id in selected:
            store = self.run_collection.run_store(run_id)
            if not store.run_record_path.exists():
                continue
            record = store.load_run_record()
            llm_call_count = len(store.load_llm_calls())
            tool_call_count = len(store.load_tool_calls())
            coding_action_count = len(CodingActionLogStore(self.config.paths.runs_dir, run_id).load_actions())
            recent_runs.append(
                RunInspection(
                    record=record,
                    llm_call_count=llm_call_count,
                    tool_call_count=tool_call_count,
                    coding_action_count=coding_action_count,
                )
            )
        return recent_runs

    def _load_rollups(self, *, rebuild_rollups: bool) -> ProjectRollups | None:
        if self.run_collection.rollups_path.exists():
            return self.run_collection.load_rollups()
        if rebuild_rollups and self.run_collection.runs_dir.exists():
            return self.rollup_service.rebuild_rollups()
        return None

    def _task_status_views(self, state: TaskState | None) -> tuple[list[str], list[str]]:
        if state is None:
            return [], []
        ordered_ids = self.task_service.topological_order(state)
        ready_ids: list[str] = []
        in_progress_ids: list[str] = []
        for task_id in ordered_ids:
            task = state.tasks[task_id]
            if task.status is TaskStatus.IN_PROGRESS:
                in_progress_ids.append(task.id)
            elif self.task_service.is_task_ready(task, state):
                ready_ids.append(task.id)
        return ready_ids, in_progress_ids

    def _relative_if_exists(self, path: Path) -> str | None:
        if not path.exists():
            return None
        return self.config.paths.relative_to_project_root(path)



def _format_usage(usage: UsageSummary | None) -> str:
    if usage is None:
        return "requests=0 input_tokens=0 output_tokens=0 tool_calls=0"
    return (
        f"requests={usage.requests} input_tokens={usage.input_tokens} "
        f"output_tokens={usage.output_tokens} tool_calls={usage.tool_calls}"
    )



def _format_task_event(event: TaskEvent) -> str:
    details = [event.kind.value]
    if event.task_id is not None:
        details.append(f"task={event.task_id}")
    if event.attempt_id is not None:
        details.append(f"attempt={event.attempt_id}")
    if event.actor is not None:
        details.append(f"actor={event.actor}")
    payload_summary = _summarize_event_payload(event)
    if payload_summary:
        details.append(payload_summary)
    return " ".join(details)



def _summarize_event_payload(event: TaskEvent) -> str | None:
    payload = event.payload
    if not payload:
        return None
    if "old_status" in payload and "new_status" in payload:
        return f"status={payload['old_status']}→{payload['new_status']}"
    if "status" in payload:
        status = str(payload["status"])
        summary = payload.get("summary")
        if isinstance(summary, str) and summary:
            return f"status={status} summary={_truncate(summary, limit=60)}"
        return f"status={status}"
    if "worker_kind" in payload:
        return f"worker_kind={payload['worker_kind']}"
    task_payload = payload.get("task")
    if isinstance(task_payload, dict):
        title = task_payload.get("title")
        status = task_payload.get("status")
        details: list[str] = []
        if isinstance(title, str) and title:
            details.append(f"title={_truncate(title, limit=50)}")
        if isinstance(status, str) and status:
            details.append(f"status={status}")
        if details:
            return " ".join(details)
    return None



def _truncate(value: str, *, limit: int = 120) -> str:
    if len(value) <= limit:
        return value
    return f"{value[: limit - 3]}..."


__all__ = [
    "FrameworkInspectionReport",
    "FrameworkInspectionService",
    "RunInspection",
    "TaskEventCounts",
    "TaskStatusCounts",
]
