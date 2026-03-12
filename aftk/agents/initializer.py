from __future__ import annotations

import os
from datetime import datetime
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any, Sequence

from pydantic import AwareDatetime, Field
from pydantic_ai import Agent, RunContext
from pydantic_ai.agent import AgentRunResult
from pydantic_ai.toolsets import CombinedToolset

from aftk.agents.deps import InitializerDeps
from aftk.agents.models import InitializationResult
from aftk.agents.tools import build_initializer_toolsets
from aftk.config import FrameworkConfig, FrameworkModel, FrameworkPaths
from aftk.project import PathLike as ProjectPathLike
from aftk.project import ProjectSnapshot, ProjectSnapshotService, RelativeProjectPath, utc_now
from aftk.tasks import NonEmptyString, TaskId, TaskService, TaskServiceError
from aftk_client import AsyncAftkClient


PathLike = str | os.PathLike[str]
DEFAULT_INITIALIZER_USER_PROMPT = (
    "Initialize this autoformalization project. Inspect the available project context with the provided read-only "
    "tools as needed, then return an InitializationResult containing a concise project summary, explicit assumptions "
    "and risks, and the first worker-sized task drafts."
)
_INITIALIZER_ROLE_INSTRUCTIONS = """
You are the initializer agent for the AFTK autoformalization framework.

Your job is to understand the starting state of the project and propose the first concrete tasks.

Requirements:
- inspect the entrypoint, source inventory, and Lean workspace using the provided read-only tools when helpful
- Lean file-scoped toolkit queries require an open file session first; call open(path=...) before load_node, hover, goal, or tactic tools
- if a toolkit tool says a file is not open or changed, call open(path=...) and then retry the query
- if a toolkit tool says a node id is stale, call load_node(...) again to get a fresh node id before continuing
- produce a concise project summary focused on the current formalization state and near-term goals
- list assumptions and risks explicitly when they matter
- propose worker-sized TaskDraft items that are concrete, local, and executable with limited context
- prefer tasks with clear acceptance criteria and explicit scope
- do not attempt to mutate persistent state directly; the runner will validate and commit your output
- do not invent filesystem or task-graph side effects
- because initialization creates the first tasks, TaskDraft.depends_on should normally be empty at this stage unless it refers to an already-existing task id
""".strip()


class InitializationAlreadyExistsError(RuntimeError):
    """Raised when initialization is attempted for a project that already has framework state."""


class InitializationApplyError(RuntimeError):
    """Raised when initializer output cannot be validated into persistent task state."""


class ProjectInitializationRecord(FrameworkModel):
    schema_version: int = Field(default=1, ge=1)
    project_root: str
    snapshot_path: RelativeProjectPath
    result: InitializationResult
    initial_task_ids: list[TaskId] = Field(default_factory=list)
    task_state_revision: int = Field(default=0, ge=0)
    initialized_by: NonEmptyString
    initialized_at: AwareDatetime = Field(default_factory=utc_now)


class ProjectInitializationStore:
    RECORD_FILE_NAME = "initialization.json"

    def __init__(self, root: PathLike | FrameworkPaths) -> None:
        store_root = root.project_state_dir if isinstance(root, FrameworkPaths) else Path(root)
        self.root = Path(store_root).expanduser().resolve(strict=False)
        self.record_path = self.root / self.RECORD_FILE_NAME

    def ensure_layout(self) -> None:
        self.root.mkdir(parents=True, exist_ok=True)

    def has_record(self) -> bool:
        return self.record_path.is_file()

    def save_record(self, record: ProjectInitializationRecord) -> Path:
        self.ensure_layout()
        _write_model_json(self.record_path, record, indent=2)
        return self.record_path

    def load_record(self) -> ProjectInitializationRecord:
        return ProjectInitializationRecord.model_validate_json(self.record_path.read_text(encoding="utf-8"))


def build_initializer_agent(
    model: Any | None = None,
    *,
    toolsets: Sequence[Any] | None = None,
) -> Agent[InitializerDeps, InitializationResult]:
    configured_toolsets = [_default_initializer_toolset] if toolsets is None else list(toolsets)
    agent = Agent(
        model,
        name="aftk_initializer",
        deps_type=InitializerDeps,
        output_type=InitializationResult,
        instructions=_INITIALIZER_ROLE_INSTRUCTIONS,
        toolsets=configured_toolsets,
        defer_model_check=model is None,
    )

    @agent.instructions
    def add_project_context(ctx: RunContext[InitializerDeps]) -> str:
        snapshot = ctx.deps.project_snapshot
        source_paths = _format_path_list([record.path for record in snapshot.source_inventory])
        lean_paths = _format_path_list([record.path for record in snapshot.lean_files])
        return "\n".join(
            [
                f"Project root: {snapshot.project_root}",
                f"Entrypoint path: {snapshot.entrypoint_path}",
                f"Lakefile path: {snapshot.lakefile_path}",
                f"Sources present: {'yes' if snapshot.sources_present else 'no'}",
                f"Source file count: {len(snapshot.source_inventory)}",
                f"Source files: {source_paths}",
                f"Lean file count: {len(snapshot.lean_files)}",
                f"Lean files: {lean_paths}",
                "Use the read-only project and toolkit tools to inspect details before finalizing when needed.",
            ]
        )

    return agent


class InitializerService:
    def __init__(self, config: FrameworkConfig | FrameworkPaths) -> None:
        self.config = config if isinstance(config, FrameworkConfig) else FrameworkConfig(paths=config)
        self.snapshot_service = ProjectSnapshotService(self.config)
        self.task_service = TaskService(self.config.paths.tasks_dir)
        self.store = ProjectInitializationStore(self.config.paths)

    def has_initialization(self) -> bool:
        return self.store.has_record()

    def load_initialization(self) -> ProjectInitializationRecord:
        return self.store.load_record()

    def build_deps(
        self,
        snapshot: ProjectSnapshot,
        toolkit_client: AsyncAftkClient,
    ) -> InitializerDeps:
        return InitializerDeps(
            config=self.config,
            project_snapshot=snapshot,
            toolkit_client=toolkit_client,
        )

    def prepare_snapshot(self, snapshot: ProjectSnapshot | None = None) -> ProjectSnapshot:
        if snapshot is None:
            return self.snapshot_service.build_and_save_snapshot()
        self.snapshot_service.store.save_snapshot(snapshot)
        return snapshot

    async def run_initializer(
        self,
        toolkit_client: AsyncAftkClient,
        *,
        model: Any | None = None,
        agent: Agent[InitializerDeps, InitializationResult] | None = None,
        snapshot: ProjectSnapshot | None = None,
        user_prompt: str = DEFAULT_INITIALIZER_USER_PROMPT,
        toolsets: Sequence[Any] | None = None,
        event_stream_handler: Any | None = None,
    ) -> AgentRunResult[InitializationResult]:
        chosen_snapshot = self.prepare_snapshot(snapshot)
        chosen_agent = (
            build_initializer_agent(toolsets=()) if agent is None and toolsets is not None else build_initializer_agent()
        ) if agent is None else agent
        run_model = self._resolve_run_model(model=model, agent=agent)
        run_kwargs: dict[str, Any] = {"deps": self.build_deps(chosen_snapshot, toolkit_client)}
        if run_model is not None:
            run_kwargs["model"] = run_model
        if toolsets is not None:
            run_kwargs["toolsets"] = list(toolsets)
        if event_stream_handler is not None and _supports_event_streaming(run_model, chosen_agent):
            run_kwargs["event_stream_handler"] = event_stream_handler
        return await chosen_agent.run(user_prompt, **run_kwargs)

    def apply_initialization_result(
        self,
        result: InitializationResult,
        *,
        actor: str = "initializer",
        snapshot: ProjectSnapshot | None = None,
        now: datetime | None = None,
    ) -> ProjectInitializationRecord:
        self._ensure_fresh_project_state()
        timestamp = utc_now() if now is None else now
        chosen_snapshot = self.prepare_snapshot(snapshot)
        try:
            created_tasks = self.task_service.create_tasks(result.initial_tasks, actor=actor, now=timestamp)
        except TaskServiceError as exc:
            raise InitializationApplyError(f"initializer output could not be applied: {exc}") from exc
        state = self.task_service.load_state()
        record = ProjectInitializationRecord(
            project_root=str(self.config.paths.project_root),
            snapshot_path=self.config.paths.relative_to_project_root(self.snapshot_service.store.snapshot_path),
            result=result,
            initial_task_ids=[task.id for task in created_tasks],
            task_state_revision=state.revision,
            initialized_by=actor,
            initialized_at=timestamp,
        )
        self.store.save_record(record)
        return record

    async def initialize(
        self,
        toolkit_client: AsyncAftkClient,
        *,
        model: Any | None = None,
        agent: Agent[InitializerDeps, InitializationResult] | None = None,
        snapshot: ProjectSnapshot | None = None,
        user_prompt: str = DEFAULT_INITIALIZER_USER_PROMPT,
        actor: str = "initializer",
        now: datetime | None = None,
        toolsets: Sequence[Any] | None = None,
    ) -> ProjectInitializationRecord:
        self._ensure_fresh_project_state()
        chosen_snapshot = self.prepare_snapshot(snapshot)
        run_result = await self.run_initializer(
            toolkit_client,
            model=model,
            agent=agent,
            snapshot=chosen_snapshot,
            user_prompt=user_prompt,
            toolsets=toolsets,
        )
        return self.apply_initialization_result(
            run_result.output,
            actor=actor,
            snapshot=chosen_snapshot,
            now=now,
        )

    def _ensure_fresh_project_state(self) -> None:
        if self.store.has_record():
            raise InitializationAlreadyExistsError(
                f"project is already initialized: {self.store.record_path}"
            )
        state = self.task_service.load_state()
        if state.tasks:
            raise InitializationAlreadyExistsError(
                "task state already contains tasks; refusing to seed initializer output twice"
            )

    def _resolve_run_model(
        self,
        *,
        model: Any | None,
        agent: Agent[InitializerDeps, InitializationResult] | None,
    ) -> Any | None:
        if model is not None:
            return model
        if agent is not None:
            return None
        if self.config.models.initializer is None:
            raise ValueError(
                "initializer model is not configured; pass model=... or set config.models.initializer"
            )
        return self.config.models.initializer


def _default_initializer_toolset(ctx: RunContext[InitializerDeps]) -> Any:
    return CombinedToolset(toolsets=list(build_initializer_toolsets(ctx.deps.project_snapshot, ctx.deps.toolkit_client)))


def _supports_event_streaming(model: Any | None, agent: Agent[InitializerDeps, InitializationResult]) -> bool:
    candidate = model if model is not None else agent.model
    if candidate is None:
        return True
    if hasattr(candidate, "stream_function") and getattr(candidate, "stream_function") is None:
        return False
    return True


def _format_path_list(paths: Sequence[ProjectPathLike], *, limit: int = 12) -> str:
    if not paths:
        return "(none)"
    rendered = [str(path) for path in paths[:limit]]
    if len(paths) > limit:
        rendered.append(f"... (+{len(paths) - limit} more)")
    return ", ".join(rendered)


def _write_model_json(path: Path, model: FrameworkModel, *, indent: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = model.model_dump_json(indent=indent)
    with NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f"{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        handle.write(payload)
        handle.write("\n")
        temp_path = Path(handle.name)
    temp_path.replace(path)


__all__ = [
    "DEFAULT_INITIALIZER_USER_PROMPT",
    "InitializationApplyError",
    "InitializationAlreadyExistsError",
    "InitializerService",
    "ProjectInitializationRecord",
    "ProjectInitializationStore",
    "build_initializer_agent",
]
