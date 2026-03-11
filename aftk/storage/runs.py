from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Annotated, Any

from pydantic import AwareDatetime, BaseModel, Field, model_validator

from aftk.config import FrameworkConfig, FrameworkPaths, FrameworkModel
from aftk.storage.costs import CostSummary, PricingTable, estimate_usage_cost, sum_costs
from aftk.storage.telemetry import LlmCallRecord, ToolCallRecord, UsageSummary, summarize_usage, utc_now


PathLike = str | os.PathLike[str]
RunId = Annotated[str, Field(min_length=1)]
RelativeRunPath = Annotated[str, Field(min_length=1)]
_RUN_ID_PATTERN = re.compile(r"^run-(?P<number>\d+)$")


class AgentRole(StrEnum):
    INITIALIZER = "initializer"
    ORCHESTRATOR = "orchestrator"
    WORKER = "worker"


class RunStatus(StrEnum):
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class RunArtifacts(FrameworkModel):
    result_path: RelativeRunPath | None = None
    messages_path: RelativeRunPath | None = None
    llm_call_log_path: RelativeRunPath | None = None
    tool_call_log_path: RelativeRunPath | None = None
    usage_path: RelativeRunPath | None = None
    cost_path: RelativeRunPath | None = None
    coding_action_log_path: RelativeRunPath | None = None


class AgentRunRecord(FrameworkModel):
    schema_version: int = Field(default=1, ge=1)
    run_id: RunId
    agent_role: AgentRole
    status: RunStatus = RunStatus.RUNNING
    project_root: str
    task_id: str | None = None
    attempt_id: str | None = None
    model_name: str | None = None
    started_at: AwareDatetime = Field(default_factory=utc_now)
    finished_at: AwareDatetime | None = None
    duration_seconds: float | None = Field(default=None, ge=0)
    error_message: str | None = None
    usage_summary: UsageSummary | None = None
    cost_summary: CostSummary | None = None
    artifacts: RunArtifacts = Field(default_factory=RunArtifacts)
    metadata: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_timestamps(self) -> AgentRunRecord:
        if self.finished_at is None:
            if self.status is not RunStatus.RUNNING:
                raise ValueError("finished_at is required once a run leaves the running state")
            if self.duration_seconds is not None:
                raise ValueError("duration_seconds is only valid once finished_at is set")
        else:
            if self.finished_at < self.started_at:
                raise ValueError("finished_at must not be earlier than started_at")
            if self.duration_seconds is None:
                raise ValueError("duration_seconds is required once finished_at is set")
        return self


class RollupBucket(FrameworkModel):
    usage: UsageSummary = Field(default_factory=UsageSummary)
    total_cost: float = Field(default=0.0, ge=0)
    run_count: int = Field(default=0, ge=0)
    llm_call_count: int = Field(default=0, ge=0)
    tool_call_count: int = Field(default=0, ge=0)

    def add(
        self,
        *,
        usage: UsageSummary | object | None = None,
        total_cost: float = 0.0,
        run_count: int = 0,
        llm_call_count: int = 0,
        tool_call_count: int = 0,
    ) -> RollupBucket:
        usage_summary = UsageSummary.from_value(usage)
        return RollupBucket(
            usage=self.usage.add(usage_summary),
            total_cost=self.total_cost + total_cost,
            run_count=self.run_count + run_count,
            llm_call_count=self.llm_call_count + llm_call_count,
            tool_call_count=self.tool_call_count + tool_call_count,
        )


class ProjectRollups(FrameworkModel):
    project_root: str
    generated_at: AwareDatetime = Field(default_factory=utc_now)
    by_run: dict[str, RollupBucket] = Field(default_factory=dict)
    by_attempt: dict[str, RollupBucket] = Field(default_factory=dict)
    by_agent_role: dict[str, RollupBucket] = Field(default_factory=dict)
    by_model: dict[str, RollupBucket] = Field(default_factory=dict)
    project: RollupBucket = Field(default_factory=RollupBucket)


@dataclass(frozen=True, slots=True)
class _RunContext:
    project_root: Path
    runs_dir: Path


class RunCollection:
    def __init__(self, project: FrameworkConfig | FrameworkPaths | PathLike) -> None:
        context = _resolve_context(project)
        self.project_root = context.project_root
        self.runs_dir = context.runs_dir
        self.rollups_path = self.runs_dir / "project-rollups.json"

    def ensure_layout(self) -> None:
        self.runs_dir.mkdir(parents=True, exist_ok=True)

    def list_run_ids(self) -> list[str]:
        if not self.runs_dir.exists():
            return []
        run_ids: list[str] = []
        for path in sorted(self.runs_dir.iterdir()):
            if path.is_dir() and path.name:
                run_ids.append(path.name)
        return run_ids

    def next_run_id(self) -> str:
        next_number = 1
        for run_id in self.list_run_ids():
            match = _RUN_ID_PATTERN.match(run_id)
            if match is None:
                continue
            next_number = max(next_number, int(match.group("number")) + 1)
        return f"run-{next_number:04d}"

    def run_store(self, run_id: str) -> RunLogStore:
        return RunLogStore(self, run_id)

    def save_rollups(self, rollups: ProjectRollups) -> Path:
        self.ensure_layout()
        _write_model_json(self.rollups_path, rollups, indent=2)
        return self.rollups_path

    def load_rollups(self) -> ProjectRollups:
        return ProjectRollups.model_validate_json(self.rollups_path.read_text(encoding="utf-8"))


class RunLogStore:
    RUN_RECORD_FILE_NAME = "run.json"
    RESULT_FILE_NAME = "result.json"
    MESSAGES_FILE_NAME = "messages.json"
    LLM_CALLS_FILE_NAME = "llm-calls.jsonl"
    TOOL_CALLS_FILE_NAME = "tool-calls.jsonl"
    USAGE_FILE_NAME = "usage.json"
    COST_FILE_NAME = "cost.json"
    CODING_ACTIONS_FILE_NAME = "coding-actions.jsonl"

    def __init__(self, project: RunCollection | FrameworkConfig | FrameworkPaths | PathLike, run_id: str) -> None:
        if not run_id:
            raise ValueError("run_id must not be empty")
        if isinstance(project, RunCollection):
            self.project_root = project.project_root
            self.runs_dir = project.runs_dir
        else:
            context = _resolve_context(project)
            self.project_root = context.project_root
            self.runs_dir = context.runs_dir
        self.run_id = run_id
        self.run_dir = self.runs_dir / run_id
        self.run_record_path = self.run_dir / self.RUN_RECORD_FILE_NAME
        self.result_path = self.run_dir / self.RESULT_FILE_NAME
        self.messages_path = self.run_dir / self.MESSAGES_FILE_NAME
        self.llm_calls_path = self.run_dir / self.LLM_CALLS_FILE_NAME
        self.tool_calls_path = self.run_dir / self.TOOL_CALLS_FILE_NAME
        self.usage_path = self.run_dir / self.USAGE_FILE_NAME
        self.cost_path = self.run_dir / self.COST_FILE_NAME
        self.coding_actions_path = self.run_dir / self.CODING_ACTIONS_FILE_NAME

    def ensure_layout(self) -> None:
        self.run_dir.mkdir(parents=True, exist_ok=True)

    def default_artifacts(self) -> RunArtifacts:
        return RunArtifacts(
            result_path=self.relative_to_project(self.result_path),
            messages_path=self.relative_to_project(self.messages_path),
            llm_call_log_path=self.relative_to_project(self.llm_calls_path),
            tool_call_log_path=self.relative_to_project(self.tool_calls_path),
            usage_path=self.relative_to_project(self.usage_path),
            cost_path=self.relative_to_project(self.cost_path),
            coding_action_log_path=self.relative_to_project(self.coding_actions_path),
        )

    def relative_to_project(self, path: PathLike) -> RelativeRunPath:
        candidate = Path(path).expanduser()
        if not candidate.is_absolute():
            candidate = self.project_root / candidate
        resolved = candidate.resolve(strict=False)
        try:
            relative = resolved.relative_to(self.project_root)
        except ValueError as exc:
            raise ValueError(f"path {resolved} is not inside project_root {self.project_root}") from exc
        return relative.as_posix()

    def save_run_record(self, record: AgentRunRecord) -> Path:
        self.ensure_layout()
        _write_model_json(self.run_record_path, record, indent=2)
        return self.run_record_path

    def load_run_record(self) -> AgentRunRecord:
        return AgentRunRecord.model_validate_json(self.run_record_path.read_text(encoding="utf-8"))

    def save_result_payload(self, payload: BaseModel | dict[str, Any] | list[Any] | str | int | float | bool | None) -> Path:
        self.ensure_layout()
        _write_json_payload(self.result_path, payload)
        return self.result_path

    def load_result_payload(self) -> Any:
        return json.loads(self.result_path.read_text(encoding="utf-8"))

    def save_messages(self, payload: bytes | str) -> Path:
        self.ensure_layout()
        if isinstance(payload, bytes):
            _write_bytes(self.messages_path, payload)
        else:
            _write_text(self.messages_path, payload)
        return self.messages_path

    def load_messages_bytes(self) -> bytes:
        return self.messages_path.read_bytes()

    def append_llm_call(self, call: LlmCallRecord) -> Path:
        self.ensure_layout()
        with self.llm_calls_path.open("a", encoding="utf-8") as handle:
            handle.write(call.model_dump_json())
            handle.write("\n")
        return self.llm_calls_path

    def load_llm_calls(self) -> list[LlmCallRecord]:
        return _load_jsonl_models(self.llm_calls_path, LlmCallRecord)

    def append_tool_call(self, call: ToolCallRecord) -> Path:
        self.ensure_layout()
        with self.tool_calls_path.open("a", encoding="utf-8") as handle:
            handle.write(call.model_dump_json())
            handle.write("\n")
        return self.tool_calls_path

    def load_tool_calls(self) -> list[ToolCallRecord]:
        return _load_jsonl_models(self.tool_calls_path, ToolCallRecord)

    def save_usage_summary(self, usage: UsageSummary) -> Path:
        self.ensure_layout()
        _write_model_json(self.usage_path, usage, indent=2)
        return self.usage_path

    def load_usage_summary(self) -> UsageSummary:
        return UsageSummary.model_validate_json(self.usage_path.read_text(encoding="utf-8"))

    def save_cost_summary(self, cost: CostSummary) -> Path:
        self.ensure_layout()
        _write_model_json(self.cost_path, cost, indent=2)
        return self.cost_path

    def load_cost_summary(self) -> CostSummary:
        return CostSummary.model_validate_json(self.cost_path.read_text(encoding="utf-8"))


class RunTelemetrySession:
    def __init__(self, store: RunLogStore, *, pricing_table: PricingTable | None = None) -> None:
        self.store = store
        self.pricing_table = pricing_table

    def start_run(
        self,
        *,
        agent_role: AgentRole,
        model_name: str | None = None,
        task_id: str | None = None,
        attempt_id: str | None = None,
        now: datetime | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> AgentRunRecord:
        timestamp = utc_now() if now is None else now
        record = AgentRunRecord(
            run_id=self.store.run_id,
            agent_role=agent_role,
            status=RunStatus.RUNNING,
            project_root=str(self.store.project_root),
            task_id=task_id,
            attempt_id=attempt_id,
            model_name=model_name,
            started_at=timestamp,
            finished_at=None,
            duration_seconds=None,
            error_message=None,
            usage_summary=None,
            cost_summary=None,
            artifacts=self.store.default_artifacts(),
            metadata={} if metadata is None else dict(metadata),
        )
        self.store.save_run_record(record)
        return record

    def save_result_payload(self, payload: BaseModel | dict[str, Any] | list[Any] | str | int | float | bool | None) -> Path:
        return self.store.save_result_payload(payload)

    def save_messages(self, payload: bytes | str) -> Path:
        return self.store.save_messages(payload)

    def save_messages_from_result(
        self,
        result: object,
        *,
        new_only: bool = True,
        output_tool_return_content: str | None = None,
    ) -> Path:
        method_name = "new_messages_json" if new_only else "all_messages_json"
        try:
            method = getattr(result, method_name)
        except AttributeError as exc:
            raise TypeError(f"result object does not expose {method_name}()") from exc
        payload = method(output_tool_return_content=output_tool_return_content)
        if not isinstance(payload, (bytes, str)):
            raise TypeError(f"{method_name}() must return bytes or str")
        return self.store.save_messages(payload)

    def append_llm_call(self, call: LlmCallRecord) -> Path:
        return self.store.append_llm_call(call)

    def append_tool_call(self, call: ToolCallRecord) -> Path:
        return self.store.append_tool_call(call)

    def usage_from_result(self, result: object) -> UsageSummary:
        usage_method = getattr(result, "usage", None)
        if usage_method is None or not callable(usage_method):
            raise TypeError("result object does not expose usage()")
        return UsageSummary.from_value(usage_method())

    def finalize_run(
        self,
        *,
        status: RunStatus,
        error_message: str | None = None,
        run_usage: UsageSummary | dict[str, object] | object | None = None,
        now: datetime | None = None,
    ) -> AgentRunRecord:
        if status is RunStatus.RUNNING:
            raise ValueError("finalize_run() requires a non-running status")
        record = self.store.load_run_record()
        if record.status is not RunStatus.RUNNING:
            raise ValueError(f"run {record.run_id!r} has already been finalized")

        timestamp = utc_now() if now is None else now
        llm_calls = self.store.load_llm_calls()
        tool_calls = self.store.load_tool_calls()
        usage_summary = self._build_usage_summary(run_usage, llm_calls, tool_calls)
        cost_summary = self._build_cost_summary(record, usage_summary, llm_calls)

        self.store.save_usage_summary(usage_summary)
        self.store.save_cost_summary(cost_summary)

        finished_record = record.model_copy(
            update={
                "status": status,
                "finished_at": timestamp,
                "duration_seconds": max((timestamp - record.started_at).total_seconds(), 0.0),
                "error_message": error_message,
                "usage_summary": usage_summary,
                "cost_summary": cost_summary,
            }
        )
        self.store.save_run_record(finished_record)
        return finished_record

    def _build_usage_summary(
        self,
        run_usage: UsageSummary | dict[str, object] | object | None,
        llm_calls: list[LlmCallRecord],
        tool_calls: list[ToolCallRecord],
    ) -> UsageSummary:
        if run_usage is None:
            return summarize_usage(llm_calls, tool_calls)

        usage_summary = UsageSummary.from_value(run_usage)
        if usage_summary.requests == 0 and llm_calls:
            usage_summary = usage_summary.model_copy(update={"requests": len(llm_calls)})
        if usage_summary.tool_calls == 0 and tool_calls:
            usage_summary = usage_summary.model_copy(
                update={
                    "tool_calls": sum(1 for call in tool_calls if call.status.value == "succeeded")
                }
            )
        return usage_summary

    def _build_cost_summary(
        self,
        record: AgentRunRecord,
        usage_summary: UsageSummary,
        llm_calls: list[LlmCallRecord],
    ) -> CostSummary:
        call_costs: list[CostSummary] = []
        for call in llm_calls:
            if call.estimated_cost is not None:
                call_costs.append(
                    CostSummary(
                        currency=self.pricing_table.currency if self.pricing_table is not None else "USD",
                        model_name=call.model_name,
                        pricing_source=self.pricing_table.source if self.pricing_table is not None else None,
                        pricing_found=True,
                        other_cost=call.estimated_cost,
                        total_cost=call.estimated_cost,
                    )
                )
                continue
            if call.model_name is None:
                continue
            call_costs.append(
                estimate_usage_cost(
                    call.usage,
                    model_name=call.model_name,
                    pricing_table=self.pricing_table,
                )
            )

        if call_costs:
            currency = call_costs[0].currency
            return sum_costs(call_costs, currency=currency)

        return estimate_usage_cost(
            usage_summary,
            model_name=record.model_name,
            pricing_table=self.pricing_table,
        )


class ProjectRollupService:
    def __init__(
        self,
        project: RunCollection | FrameworkConfig | FrameworkPaths | PathLike,
        *,
        pricing_table: PricingTable | None = None,
    ) -> None:
        self.collection = project if isinstance(project, RunCollection) else RunCollection(project)
        self.pricing_table = pricing_table

    def rebuild_rollups(self) -> ProjectRollups:
        rollups = ProjectRollups(project_root=str(self.collection.project_root))
        for run_id in self.collection.list_run_ids():
            store = self.collection.run_store(run_id)
            if not store.run_record_path.exists():
                continue
            record = store.load_run_record()
            llm_calls = store.load_llm_calls()
            tool_calls = store.load_tool_calls()
            usage = record.usage_summary if record.usage_summary is not None else self._load_usage_fallback(store, llm_calls, tool_calls)
            cost = record.cost_summary if record.cost_summary is not None else self._load_cost_fallback(store)
            rollups = self._add_run_rollups(rollups, record=record, llm_calls=llm_calls, tool_calls=tool_calls, usage=usage, cost=cost)
        self.collection.save_rollups(rollups)
        return rollups

    def _load_usage_fallback(
        self,
        store: RunLogStore,
        llm_calls: list[LlmCallRecord],
        tool_calls: list[ToolCallRecord],
    ) -> UsageSummary:
        if store.usage_path.exists():
            return store.load_usage_summary()
        return summarize_usage(llm_calls, tool_calls)

    def _load_cost_fallback(self, store: RunLogStore) -> CostSummary:
        if store.cost_path.exists():
            return store.load_cost_summary()
        return CostSummary(total_cost=0.0)

    def _add_run_rollups(
        self,
        rollups: ProjectRollups,
        *,
        record: AgentRunRecord,
        llm_calls: list[LlmCallRecord],
        tool_calls: list[ToolCallRecord],
        usage: UsageSummary,
        cost: CostSummary,
    ) -> ProjectRollups:
        by_run = dict(rollups.by_run)
        by_run[record.run_id] = by_run.get(record.run_id, RollupBucket()).add(
            usage=usage,
            total_cost=cost.total_cost,
            run_count=1,
            llm_call_count=len(llm_calls),
            tool_call_count=len(tool_calls),
        )

        by_attempt = dict(rollups.by_attempt)
        if record.attempt_id is not None:
            by_attempt[record.attempt_id] = by_attempt.get(record.attempt_id, RollupBucket()).add(
                usage=usage,
                total_cost=cost.total_cost,
                run_count=1,
                llm_call_count=len(llm_calls),
                tool_call_count=len(tool_calls),
            )

        by_agent_role = dict(rollups.by_agent_role)
        role_key = record.agent_role.value
        by_agent_role[role_key] = by_agent_role.get(role_key, RollupBucket()).add(
            usage=usage,
            total_cost=cost.total_cost,
            run_count=1,
            llm_call_count=len(llm_calls),
            tool_call_count=len(tool_calls),
        )

        by_model = dict(rollups.by_model)
        if llm_calls:
            for call in llm_calls:
                if call.model_name is None:
                    continue
                estimated_call_cost = call.estimated_cost
                if estimated_call_cost is None:
                    estimated_call_cost = estimate_usage_cost(
                        call.usage,
                        model_name=call.model_name,
                        pricing_table=self.pricing_table,
                    ).total_cost
                model_usage = call.usage if call.usage.requests else call.usage.model_copy(update={"requests": 1})
                bucket = by_model.get(call.model_name, RollupBucket())
                by_model[call.model_name] = bucket.add(
                    usage=model_usage,
                    total_cost=estimated_call_cost,
                    llm_call_count=1,
                )
        elif record.model_name is not None:
            by_model[record.model_name] = by_model.get(record.model_name, RollupBucket()).add(
                usage=usage,
                total_cost=cost.total_cost,
                run_count=1,
                llm_call_count=len(llm_calls),
            )

        project_bucket = rollups.project.add(
            usage=usage,
            total_cost=cost.total_cost,
            run_count=1,
            llm_call_count=len(llm_calls),
            tool_call_count=len(tool_calls),
        )

        return rollups.model_copy(
            update={
                "generated_at": utc_now(),
                "by_run": by_run,
                "by_attempt": by_attempt,
                "by_agent_role": by_agent_role,
                "by_model": by_model,
                "project": project_bucket,
            }
        )


def _resolve_context(project: RunCollection | FrameworkConfig | FrameworkPaths | PathLike) -> _RunContext:
    if isinstance(project, RunCollection):
        return _RunContext(project_root=project.project_root, runs_dir=project.runs_dir)
    if isinstance(project, FrameworkConfig):
        return _RunContext(project_root=project.paths.project_root, runs_dir=project.paths.runs_dir)
    if isinstance(project, FrameworkPaths):
        return _RunContext(project_root=project.project_root, runs_dir=project.runs_dir)
    root = Path(project).expanduser().resolve(strict=False)
    if not root.exists() or not root.is_dir():
        raise ValueError(f"project_root does not exist or is not a directory: {root}")
    return _RunContext(project_root=root, runs_dir=(root / ".aftk" / "runs").resolve(strict=False))


def _write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f"{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        handle.write(content)
        temp_path = Path(handle.name)
    temp_path.replace(path)


def _write_bytes(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile(
        "wb",
        dir=path.parent,
        prefix=f"{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        handle.write(content)
        temp_path = Path(handle.name)
    temp_path.replace(path)


def _write_json_payload(path: Path, payload: BaseModel | dict[str, Any] | list[Any] | str | int | float | bool | None) -> None:
    if isinstance(payload, BaseModel):
        _write_text(path, f"{payload.model_dump_json(indent=2)}\n")
        return
    _write_text(path, f"{json.dumps(payload, indent=2, sort_keys=True)}\n")


def _write_model_json(path: Path, model: BaseModel, *, indent: int | None = None) -> None:
    _write_text(path, f"{model.model_dump_json(indent=indent)}\n")


def _load_jsonl_models(path: Path, model_type: type[BaseModel]) -> list[BaseModel]:
    if not path.exists():
        return []
    models: list[BaseModel] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            payload = line.strip()
            if not payload:
                continue
            models.append(model_type.model_validate_json(payload))
    return models


__all__ = [
    "AgentRole",
    "AgentRunRecord",
    "ProjectRollupService",
    "ProjectRollups",
    "RollupBucket",
    "RunArtifacts",
    "RunCollection",
    "RunId",
    "RunLogStore",
    "RunStatus",
    "RunTelemetrySession",
]
