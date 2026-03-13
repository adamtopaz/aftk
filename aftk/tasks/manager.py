from __future__ import annotations

from collections.abc import Awaitable, Callable, Iterable, Sequence
from pathlib import Path
from typing import Any

from aftk.tasks.graph import (
    blocked_tasks,
    dependency_tasks,
    incomplete_tasks,
    ready_tasks,
    scheduler_status,
    terminal_tasks,
    validate_task_graph,
)
from aftk.tasks.models import (
    TaskArtifact,
    TaskAttempt,
    TaskAttemptStatus,
    TaskExecutionResult,
    TaskExecutionStatus,
    TaskLifecycleStatus,
    TaskRecord,
    TaskRunState,
    TaskSchedulerStatus,
    TaskSpec,
    utc_now,
)
from aftk.tasks.store import FileTaskRunStore, TaskRunStore


class TaskManagerError(RuntimeError):
    """Base error raised for task-manager failures."""


class TaskConflictError(TaskManagerError):
    """Raised when a caller attempts an invalid structural change."""


class TaskNotFoundError(TaskManagerError, KeyError):
    """Raised when a requested task id does not exist."""


class TaskTransitionError(TaskManagerError):
    """Raised when a task lifecycle transition is invalid."""


TaskExecutor = Callable[[TaskRecord], Awaitable[TaskExecutionResult]]


class TaskManager:
    def __init__(self, store: TaskRunStore, state: TaskRunState) -> None:
        validate_task_graph(state.tasks)
        self._store = store
        self._state = state

    @property
    def run_id(self) -> str:
        return self._state.run_id

    @property
    def state(self) -> TaskRunState:
        return self._state.model_copy(deep=True)

    @classmethod
    def create(
        cls,
        store: TaskRunStore,
        run_id: str,
        *,
        metadata: dict[str, Any] | None = None,
    ) -> TaskManager:
        if store.exists():
            raise TaskConflictError("task store already contains a run state")
        state = TaskRunState(run_id=run_id, metadata=dict(metadata or {}))
        store.save(state)
        return cls(store, state)

    @classmethod
    def create_in_file(
        cls,
        path: str | Path,
        run_id: str,
        *,
        metadata: dict[str, Any] | None = None,
    ) -> TaskManager:
        return cls.create(FileTaskRunStore(path), run_id, metadata=metadata)

    @classmethod
    def load(cls, store: TaskRunStore) -> TaskManager:
        return cls(store, store.load())

    def validate(self) -> None:
        validate_task_graph(self._state.tasks)

    def get_task(self, task_id: str) -> TaskRecord:
        return self._task(task_id).model_copy(deep=True)

    def list_tasks(self) -> list[TaskRecord]:
        return [task.model_copy(deep=True) for task in ready_tasks(self._state.tasks) + self._non_ready_non_terminal() + terminal_tasks(self._state.tasks)]

    def ready_tasks(self) -> list[TaskRecord]:
        return [task.model_copy(deep=True) for task in ready_tasks(self._state.tasks)]

    def blocked_tasks(self) -> list[TaskRecord]:
        return [task.model_copy(deep=True) for task in blocked_tasks(self._state.tasks)]

    def terminal_tasks(self) -> list[TaskRecord]:
        return [task.model_copy(deep=True) for task in terminal_tasks(self._state.tasks)]

    def incomplete_tasks(self) -> list[TaskRecord]:
        return [task.model_copy(deep=True) for task in incomplete_tasks(self._state.tasks)]

    def dependency_tasks(self, task_id: str) -> list[TaskRecord]:
        task = self._task(task_id)
        return [dependency.model_copy(deep=True) for dependency in dependency_tasks(task, self._state.tasks)]

    def scheduler_status(self, task_id: str) -> TaskSchedulerStatus:
        return scheduler_status(self._task(task_id), self._state.tasks)

    def add_task(self, task: TaskSpec | TaskRecord) -> TaskRecord:
        return self.add_tasks([task])[0]

    def add_tasks(self, tasks: Iterable[TaskSpec | TaskRecord]) -> list[TaskRecord]:
        records = [self._record_for(task) for task in tasks]
        if not records:
            return []

        def mutate(state: TaskRunState) -> None:
            seen: set[str] = set()
            for record in records:
                if record.id in seen:
                    raise TaskConflictError(f"duplicate task id in batch: {record.id!r}")
                if record.id in state.tasks:
                    raise TaskConflictError(f"task {record.id!r} already exists")
                seen.add(record.id)
            for record in records:
                state.tasks[record.id] = record.model_copy(deep=True)

        self._mutate(mutate, validate_graph=True)
        return [self.get_task(record.id) for record in records]

    def add_dependency(self, task_id: str, dependency_id: str) -> TaskRecord:
        def mutate(state: TaskRunState) -> None:
            task = self._task_from_state(state, task_id)
            if dependency_id in task.depends_on:
                raise TaskConflictError(
                    f"task {task_id!r} already depends on {dependency_id!r}"
                )
            task.depends_on.append(dependency_id)
            task.updated_at = utc_now()

        self._mutate(mutate, validate_graph=True)
        return self.get_task(task_id)

    def claim_task(self, task_id: str, *, runner_id: str | None = None) -> TaskRecord:
        def mutate(state: TaskRunState) -> None:
            task = self._task_from_state(state, task_id)
            if scheduler_status(task, state.tasks) != TaskSchedulerStatus.ready:
                raise TaskTransitionError(f"task {task_id!r} is not ready to run")
            if task.max_attempts is not None and len(task.attempts) >= task.max_attempts:
                raise TaskTransitionError(f"task {task_id!r} has exhausted max_attempts")

            started_at = utc_now()
            task.status = TaskLifecycleStatus.running
            task.started_at = started_at
            task.finished_at = None
            task.claimed_by = runner_id
            task.updated_at = started_at
            task.result_summary = None
            task.last_error = None
            task.attempts.append(
                TaskAttempt(
                    attempt=len(task.attempts) + 1,
                    started_at=started_at,
                    runner_id=runner_id,
                    status=TaskAttemptStatus.running,
                )
            )

        self._mutate(mutate)
        return self.get_task(task_id)

    def complete_task(
        self,
        task_id: str,
        *,
        summary: str | None = None,
        artifacts: Sequence[TaskArtifact] | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> TaskRecord:
        def mutate(state: TaskRunState) -> None:
            task = self._task_from_state(state, task_id)
            attempt = self._active_attempt(task)
            finished_at = utc_now()
            attempt.status = TaskAttemptStatus.completed
            attempt.finished_at = finished_at
            attempt.summary = summary
            if metadata is not None:
                attempt.metadata.update(metadata)
                task.metadata.update(metadata)
            if artifacts is not None:
                task.artifacts.extend(artifact.model_copy(deep=True) for artifact in artifacts)
            task.status = TaskLifecycleStatus.completed
            task.claimed_by = None
            task.finished_at = finished_at
            task.updated_at = finished_at
            task.result_summary = summary
            task.last_error = None

        self._mutate(mutate)
        return self.get_task(task_id)

    def fail_task(
        self,
        task_id: str,
        *,
        error_message: str,
        summary: str | None = None,
        artifacts: Sequence[TaskArtifact] | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> TaskRecord:
        def mutate(state: TaskRunState) -> None:
            task = self._task_from_state(state, task_id)
            attempt = self._active_attempt(task)
            finished_at = utc_now()
            attempt.status = TaskAttemptStatus.failed
            attempt.finished_at = finished_at
            attempt.summary = summary
            attempt.error_message = error_message
            if metadata is not None:
                attempt.metadata.update(metadata)
                task.metadata.update(metadata)
            if artifacts is not None:
                task.artifacts.extend(artifact.model_copy(deep=True) for artifact in artifacts)
            task.status = TaskLifecycleStatus.failed
            task.claimed_by = None
            task.finished_at = finished_at
            task.updated_at = finished_at
            task.result_summary = summary
            task.last_error = error_message

        self._mutate(mutate)
        return self.get_task(task_id)

    def cancel_task(
        self,
        task_id: str,
        *,
        summary: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> TaskRecord:
        def mutate(state: TaskRunState) -> None:
            task = self._task_from_state(state, task_id)
            finished_at = utc_now()
            if task.status == TaskLifecycleStatus.running:
                attempt = self._active_attempt(task)
                attempt.status = TaskAttemptStatus.canceled
                attempt.finished_at = finished_at
                attempt.summary = summary
                if metadata is not None:
                    attempt.metadata.update(metadata)
            elif task.status != TaskLifecycleStatus.pending:
                raise TaskTransitionError(f"task {task_id!r} cannot be canceled from {task.status.value!r}")

            if metadata is not None:
                task.metadata.update(metadata)
            task.status = TaskLifecycleStatus.canceled
            task.claimed_by = None
            task.finished_at = finished_at
            task.updated_at = finished_at
            task.result_summary = summary

        self._mutate(mutate)
        return self.get_task(task_id)

    def requeue_task(self, task_id: str, *, clear_error: bool = True) -> TaskRecord:
        def mutate(state: TaskRunState) -> None:
            task = self._task_from_state(state, task_id)
            if task.status != TaskLifecycleStatus.failed:
                raise TaskTransitionError(f"task {task_id!r} is not failed and cannot be requeued")
            if task.max_attempts is not None and len(task.attempts) >= task.max_attempts:
                raise TaskTransitionError(f"task {task_id!r} has exhausted max_attempts")
            task.status = TaskLifecycleStatus.pending
            task.claimed_by = None
            task.started_at = None
            task.finished_at = None
            task.updated_at = utc_now()
            task.result_summary = None
            if clear_error:
                task.last_error = None

        self._mutate(mutate)
        return self.get_task(task_id)

    def attach_artifact(self, task_id: str, artifact: TaskArtifact) -> TaskRecord:
        def mutate(state: TaskRunState) -> None:
            task = self._task_from_state(state, task_id)
            task.artifacts.append(artifact.model_copy(deep=True))
            task.updated_at = utc_now()

        self._mutate(mutate)
        return self.get_task(task_id)

    def attach_note(self, task_id: str, text: str, *, metadata: dict[str, Any] | None = None) -> TaskRecord:
        return self.attach_artifact(
            task_id,
            TaskArtifact(kind="note", value=text, metadata=dict(metadata or {})),
        )

    def _task(self, task_id: str) -> TaskRecord:
        return self._task_from_state(self._state, task_id)

    def _task_from_state(self, state: TaskRunState, task_id: str) -> TaskRecord:
        try:
            return state.tasks[task_id]
        except KeyError as exc:
            raise TaskNotFoundError(task_id) from exc

    def _active_attempt(self, task: TaskRecord) -> TaskAttempt:
        if task.status != TaskLifecycleStatus.running:
            raise TaskTransitionError(f"task {task.id!r} is not running")
        if not task.attempts:
            raise TaskTransitionError(f"task {task.id!r} has no active attempt")
        attempt = task.attempts[-1]
        if attempt.status != TaskAttemptStatus.running:
            raise TaskTransitionError(f"task {task.id!r} has no running attempt")
        return attempt

    def _record_for(self, task: TaskSpec | TaskRecord) -> TaskRecord:
        if isinstance(task, TaskRecord):
            return task.model_copy(deep=True)
        return TaskRecord(**task.model_dump())

    def _mutate(self, mutator: Callable[[TaskRunState], None], *, validate_graph: bool = False) -> None:
        next_state = self._state.model_copy(deep=True)
        mutator(next_state)
        if validate_graph:
            validate_task_graph(next_state.tasks)
        next_state.updated_at = utc_now()
        self._store.save(next_state)
        self._state = next_state

    def _non_ready_non_terminal(self) -> list[TaskRecord]:
        return [
            task.model_copy(deep=True)
            for task in sorted(
                (
                    task
                    for task in self._state.tasks.values()
                    if scheduler_status(task, self._state.tasks)
                    not in {TaskSchedulerStatus.ready, TaskSchedulerStatus.completed, TaskSchedulerStatus.failed, TaskSchedulerStatus.canceled}
                ),
                key=lambda task: (-task.priority, task.id),
            )
        ]


async def execute_next_ready_task(
    manager: TaskManager,
    executor: TaskExecutor,
    *,
    runner_id: str | None = None,
) -> TaskRecord | None:
    ready = manager.ready_tasks()
    if not ready:
        return None

    task_id = ready[0].id
    task = manager.claim_task(task_id, runner_id=runner_id)
    try:
        result = await executor(task)
    except Exception as exc:
        manager.fail_task(task_id, error_message=str(exc) or exc.__class__.__name__)
        return manager.get_task(task_id)

    if result.status == TaskExecutionStatus.completed:
        manager.complete_task(
            task_id,
            summary=result.summary,
            artifacts=result.artifacts,
            metadata=result.metadata,
        )
    elif result.status == TaskExecutionStatus.failed:
        assert result.error_message is not None
        manager.fail_task(
            task_id,
            error_message=result.error_message,
            summary=result.summary,
            artifacts=result.artifacts,
            metadata=result.metadata,
        )
    else:
        manager.cancel_task(task_id, summary=result.summary, metadata=result.metadata)

    return manager.get_task(task_id)


async def execute_ready_tasks_until_blocked(
    manager: TaskManager,
    executor: TaskExecutor,
    *,
    runner_id: str | None = None,
    limit: int | None = None,
) -> list[TaskRecord]:
    if limit is not None and limit < 0:
        raise ValueError("limit must be non-negative")

    completed_runs: list[TaskRecord] = []
    while limit is None or len(completed_runs) < limit:
        task = await execute_next_ready_task(manager, executor, runner_id=runner_id)
        if task is None:
            break
        completed_runs.append(task)
    return completed_runs
