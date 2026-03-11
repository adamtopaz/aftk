from __future__ import annotations

import os
import re
from collections import defaultdict, deque
from collections.abc import Iterable, Sequence
from datetime import datetime
from pathlib import Path

from aftk.tasks.models import (
    AttemptId,
    SummaryValue,
    Task,
    TaskAttempt,
    TaskAttemptStatus,
    TaskDraft,
    TaskEvent,
    TaskEventKind,
    TaskId,
    TaskNote,
    TaskPatch,
    TaskState,
    TaskStatus,
    utc_now,
)
from aftk.tasks.store import TaskStore


PathLike = str | os.PathLike[str]
TERMINAL_TASK_STATUSES = frozenset({TaskStatus.COMPLETED, TaskStatus.FAILED, TaskStatus.CANCELLED})
_DYNAMIC_TASK_STATUSES = frozenset({TaskStatus.PLANNED, TaskStatus.READY})
_ID_TEMPLATE = re.compile(r"^(?P<prefix>[a-z_]+)-(?P<number>\d+)$")


class TaskServiceError(Exception):
    """Base exception for task-system service failures."""


class TaskGraphError(TaskServiceError):
    """The task graph violates dependency or status invariants."""


class TaskNotFoundError(TaskServiceError):
    """A referenced task id does not exist."""


class TaskNotReadyError(TaskServiceError):
    """A task cannot be claimed because it is not ready."""


class AttemptNotFoundError(TaskServiceError):
    """A referenced task attempt does not exist."""


class AttemptStateError(TaskServiceError):
    """A task attempt cannot transition in the requested way."""


class TaskService:
    def __init__(self, store: TaskStore | PathLike) -> None:
        self.store = store if isinstance(store, TaskStore) else TaskStore(store)

    def load_state(self) -> TaskState:
        state = self.store.load_or_create_state()
        self.validate_state(state)
        return state

    def list_ready_tasks(self) -> list[Task]:
        state = self.load_state()
        return [task for task in self._tasks_in_topological_order(state) if self.is_task_ready(task, state)]

    def list_blocked_tasks(self) -> list[Task]:
        state = self.load_state()
        return [task for task in self._tasks_in_topological_order(state) if task.status is TaskStatus.BLOCKED]

    def list_in_progress_tasks(self) -> list[Task]:
        state = self.load_state()
        return [task for task in self._tasks_in_topological_order(state) if task.status is TaskStatus.IN_PROGRESS]

    def topological_order(self, state: TaskState | None = None) -> list[TaskId]:
        current_state = self.load_state() if state is None else state
        return self._topological_order(current_state.tasks)

    def validate_state(self, state: TaskState) -> None:
        order = self._topological_order(state.tasks)
        for task_id in order:
            task = state.tasks[task_id]
            dependencies_completed = self._dependencies_completed(task, state.tasks)
            if task.status in {TaskStatus.READY, TaskStatus.IN_PROGRESS, TaskStatus.COMPLETED} and not dependencies_completed:
                raise TaskGraphError(
                    f"task {task.id!r} with status {task.status.value!r} requires all dependencies to be completed"
                )

    def is_task_ready(self, task: Task, state: TaskState) -> bool:
        return (
            task.status not in TERMINAL_TASK_STATUSES
            and task.status is not TaskStatus.BLOCKED
            and task.status is not TaskStatus.IN_PROGRESS
            and self._dependencies_completed(task, state.tasks)
        )

    def create_tasks(
        self,
        drafts: Sequence[TaskDraft],
        *,
        actor: str,
        now: datetime | None = None,
    ) -> list[Task]:
        if not drafts:
            return []

        timestamp = utc_now() if now is None else now
        state = self.load_state()
        tasks = dict(state.tasks)
        created_ids: list[TaskId] = []

        for draft in drafts:
            task_id = self._next_task_id(tasks.keys())
            task = Task(
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
                created_by=actor,
                updated_by=actor,
                current_attempt_id=None,
                attempt_count=0,
                created_at=timestamp,
                updated_at=timestamp,
            )
            tasks[task_id] = task
            created_ids.append(task_id)

        normalized_tasks, normalized_changes = self._normalize_tasks(tasks, actor=actor, now=timestamp)
        candidate_state = self._candidate_state(state, normalized_tasks)
        self.validate_state(candidate_state)

        committed_state = self._commit_graph_state(candidate_state, now=timestamp)
        events = [
            TaskEvent(
                kind=TaskEventKind.TASK_CREATED,
                revision=committed_state.revision,
                task_id=task_id,
                actor=actor,
                payload={"task": committed_state.tasks[task_id].model_dump(mode="json")},
            )
            for task_id in created_ids
        ]
        events.extend(self._normalization_events(committed_state, normalized_changes, actor=actor, excluded_task_ids=set(created_ids)))
        self._append_events(events)
        return [committed_state.tasks[task_id] for task_id in created_ids]

    def apply_patch(self, patch: TaskPatch, *, actor: str, now: datetime | None = None) -> Task:
        return self.apply_patches([patch], actor=actor, now=now)[0]

    def apply_patches(
        self,
        patches: Sequence[TaskPatch],
        *,
        actor: str,
        now: datetime | None = None,
    ) -> list[Task]:
        if not patches:
            return []

        timestamp = utc_now() if now is None else now
        state = self.load_state()
        tasks = dict(state.tasks)
        patch_history: list[tuple[TaskPatch, Task]] = []

        for patch in patches:
            task = tasks.get(patch.task_id)
            if task is None:
                raise TaskNotFoundError(f"unknown task id: {patch.task_id}")
            if patch.new_status is TaskStatus.IN_PROGRESS:
                raise TaskGraphError("task patches cannot set tasks to in_progress; use claim_task() instead")
            patch_history.append((patch, task))
            tasks[patch.task_id] = self._apply_single_patch(task, patch, actor=actor, now=timestamp)

        normalized_tasks, normalized_changes = self._normalize_tasks(tasks, actor=actor, now=timestamp)
        candidate_state = self._candidate_state(state, normalized_tasks)
        self.validate_state(candidate_state)

        committed_state = self._commit_graph_state(candidate_state, now=timestamp)
        direct_patch_task_ids = {patch.task_id for patch in patches}
        events = []
        for patch, old_task in patch_history:
            new_task = committed_state.tasks[patch.task_id]
            events.append(
                TaskEvent(
                    kind=TaskEventKind.TASK_PATCHED,
                    revision=committed_state.revision,
                    task_id=patch.task_id,
                    actor=actor,
                    payload={
                        "patch": patch.model_dump(mode="json"),
                        "old_status": old_task.status.value,
                        "new_status": new_task.status.value,
                    },
                )
            )
        events.extend(
            self._normalization_events(committed_state, normalized_changes, actor=actor, excluded_task_ids=direct_patch_task_ids)
        )
        self._append_events(events)
        return [committed_state.tasks[patch.task_id] for patch in patches]

    def claim_task(
        self,
        task_id: TaskId,
        *,
        actor: str,
        worker_kind: str,
        now: datetime | None = None,
    ) -> TaskAttempt:
        timestamp = utc_now() if now is None else now
        state = self.load_state()
        tasks, _ = self._normalize_tasks(state.tasks, actor=actor, now=timestamp)
        state = self._candidate_state(state, tasks)
        self.validate_state(state)

        task = state.tasks.get(task_id)
        if task is None:
            raise TaskNotFoundError(f"unknown task id: {task_id}")
        if not self.is_task_ready(task, state):
            raise TaskNotReadyError(f"task {task_id!r} is not ready and cannot be claimed")

        attempt_id = self._next_attempt_id()
        attempt = TaskAttempt(
            id=attempt_id,
            task_id=task_id,
            worker_kind=worker_kind,
            status=TaskAttemptStatus.RUNNING,
            started_at=timestamp,
            finished_at=None,
            run_id=None,
            report_path=None,
            transcript_path=None,
            llm_call_log_path=None,
            tool_call_log_path=None,
            usage_summary=None,
            cost_summary=None,
            summary=None,
        )
        updated_task = self._replace_task(
            task,
            status=TaskStatus.IN_PROGRESS,
            current_attempt_id=attempt.id,
            attempt_count=task.attempt_count + 1,
            updated_by=actor,
            updated_at=timestamp,
        )
        tasks = dict(state.tasks)
        tasks[task_id] = updated_task
        candidate_state = self._candidate_state(state, tasks)
        self.validate_state(candidate_state)

        committed_state = self._commit_graph_state(candidate_state, now=timestamp)
        self.store.save_attempt(attempt)
        self._append_events(
            [
                TaskEvent(
                    kind=TaskEventKind.TASK_CLAIMED,
                    revision=committed_state.revision,
                    task_id=task_id,
                    attempt_id=attempt.id,
                    actor=actor,
                    payload={"worker_kind": worker_kind},
                ),
                TaskEvent(
                    kind=TaskEventKind.ATTEMPT_STARTED,
                    revision=committed_state.revision,
                    task_id=task_id,
                    attempt_id=attempt.id,
                    actor=actor,
                    payload={"worker_kind": worker_kind},
                ),
            ]
        )
        return attempt

    def finish_attempt(
        self,
        attempt_id: AttemptId,
        *,
        actor: str,
        status: TaskAttemptStatus,
        summary: str | None = None,
        run_id: str | None = None,
        report_path: str | None = None,
        transcript_path: str | None = None,
        llm_call_log_path: str | None = None,
        tool_call_log_path: str | None = None,
        usage_summary: dict[str, SummaryValue] | None = None,
        cost_summary: dict[str, SummaryValue] | None = None,
        now: datetime | None = None,
    ) -> TaskAttempt:
        if status is TaskAttemptStatus.RUNNING:
            raise AttemptStateError("finish_attempt() requires a non-running attempt status")

        timestamp = utc_now() if now is None else now
        state = self.load_state()
        try:
            attempt = self.store.load_attempt(attempt_id)
        except FileNotFoundError as exc:
            raise AttemptNotFoundError(f"unknown attempt id: {attempt_id}") from exc

        if attempt.status is not TaskAttemptStatus.RUNNING:
            raise AttemptStateError(f"attempt {attempt_id!r} has already been finished")

        task = state.tasks.get(attempt.task_id)
        if task is None:
            raise TaskNotFoundError(f"unknown task id: {attempt.task_id}")
        if task.current_attempt_id not in {None, attempt_id}:
            raise AttemptStateError(
                f"attempt {attempt_id!r} is not the current active attempt for task {attempt.task_id!r}"
            )

        finished_attempt = self._replace_attempt(
            attempt,
            status=status,
            finished_at=timestamp,
            run_id=run_id,
            report_path=report_path,
            transcript_path=transcript_path,
            llm_call_log_path=llm_call_log_path,
            tool_call_log_path=tool_call_log_path,
            usage_summary=usage_summary,
            cost_summary=cost_summary,
            summary=summary,
        )
        self.store.save_attempt(finished_attempt)
        self._append_events(
            [
                TaskEvent(
                    kind=TaskEventKind.ATTEMPT_FINISHED,
                    revision=state.revision,
                    task_id=task.id,
                    attempt_id=attempt_id,
                    actor=actor,
                    payload={
                        "status": finished_attempt.status.value,
                        "summary": finished_attempt.summary,
                        "run_id": finished_attempt.run_id,
                    },
                )
            ]
        )
        return finished_attempt

    def recover_interrupted_tasks(self, *, actor: str = "system", now: datetime | None = None) -> list[Task]:
        timestamp = utc_now() if now is None else now
        state = self.load_state()
        tasks = dict(state.tasks)
        recovered_attempts: list[tuple[Task, TaskAttempt | None]] = []

        for task in self._tasks_in_topological_order(state):
            if task.status is not TaskStatus.IN_PROGRESS:
                continue
            attempt: TaskAttempt | None = None
            if task.current_attempt_id is not None:
                try:
                    attempt = self.store.load_attempt(task.current_attempt_id)
                except FileNotFoundError:
                    attempt = None
            tasks[task.id] = self._replace_task(
                task,
                status=TaskStatus.PLANNED,
                current_attempt_id=None,
                updated_by=actor,
                updated_at=timestamp,
            )
            recovered_attempts.append((task, attempt))

        if not recovered_attempts:
            return []

        normalized_tasks, _ = self._normalize_tasks(tasks, actor=actor, now=timestamp)
        candidate_state = self._candidate_state(state, normalized_tasks)
        self.validate_state(candidate_state)

        committed_state = self._commit_graph_state(candidate_state, now=timestamp)
        self._append_events(
            [
                TaskEvent(
                    kind=TaskEventKind.TASK_RECOVERED,
                    revision=committed_state.revision,
                    task_id=task.id,
                    attempt_id=task.current_attempt_id,
                    actor=actor,
                    payload={
                        "reason": "startup_recovery",
                        "old_status": task.status.value,
                        "new_status": committed_state.tasks[task.id].status.value,
                        "attempt_record_found": attempt is not None,
                        "attempt_status": None if attempt is None else attempt.status.value,
                    },
                )
                for task, attempt in recovered_attempts
            ]
        )
        return [committed_state.tasks[task.id] for task, _ in recovered_attempts]

    def _apply_single_patch(self, task: Task, patch: TaskPatch, *, actor: str, now: datetime) -> Task:
        dependencies = [dependency for dependency in task.depends_on if dependency not in set(patch.remove_dependencies)]
        dependencies.extend(patch.add_dependencies)
        notes = list(task.notes)
        notes.extend(TaskNote(author=actor, message=message, timestamp=now) for message in patch.append_notes)

        updates: dict[str, object] = {
            "depends_on": dependencies,
            "notes": notes,
            "updated_by": actor,
            "updated_at": now,
        }
        if patch.new_status is not None:
            updates["status"] = patch.new_status
            if patch.new_status is not TaskStatus.IN_PROGRESS:
                updates["current_attempt_id"] = None
        if patch.blockers is not None:
            updates["blockers"] = list(patch.blockers)
        if patch.context_summary is not None:
            updates["context_summary"] = patch.context_summary
        if patch.priority is not None:
            updates["priority"] = patch.priority
        return self._replace_task(task, **updates)

    def _normalize_tasks(
        self,
        tasks: dict[TaskId, Task],
        *,
        actor: str,
        now: datetime,
    ) -> tuple[dict[TaskId, Task], list[tuple[Task, Task]]]:
        order = self._topological_order(tasks)
        normalized_tasks = dict(tasks)
        changes: list[tuple[Task, Task]] = []
        for task_id in order:
            task = normalized_tasks[task_id]
            if task.status not in _DYNAMIC_TASK_STATUSES:
                continue
            desired_status = TaskStatus.READY if self._dependencies_completed(task, normalized_tasks) else TaskStatus.PLANNED
            if desired_status is task.status:
                continue
            normalized_task = self._replace_task(task, status=desired_status, updated_by=actor, updated_at=now)
            normalized_tasks[task_id] = normalized_task
            changes.append((task, normalized_task))
        return normalized_tasks, changes

    def _candidate_state(self, state: TaskState, tasks: dict[TaskId, Task]) -> TaskState:
        return TaskState(
            revision=state.revision,
            tasks=tasks,
            created_at=state.created_at,
            updated_at=state.updated_at,
        )

    def _commit_graph_state(self, state: TaskState, *, now: datetime) -> TaskState:
        committed_state = TaskState(
            revision=state.revision + 1,
            tasks=state.tasks,
            created_at=state.created_at,
            updated_at=now,
        )
        self.store.save_state(committed_state)
        return committed_state

    def _append_events(self, events: Sequence[TaskEvent]) -> None:
        for event in events:
            self.store.append_event(event)

    def _normalization_events(
        self,
        state: TaskState,
        changes: Sequence[tuple[Task, Task]],
        *,
        actor: str,
        excluded_task_ids: set[TaskId],
    ) -> list[TaskEvent]:
        events: list[TaskEvent] = []
        for old_task, new_task in changes:
            if new_task.id in excluded_task_ids:
                continue
            events.append(
                TaskEvent(
                    kind=TaskEventKind.TASK_PATCHED,
                    revision=state.revision,
                    task_id=new_task.id,
                    actor=actor,
                    payload={
                        "reason": "readiness_recomputed",
                        "old_status": old_task.status.value,
                        "new_status": new_task.status.value,
                    },
                )
            )
        return events

    def _tasks_in_topological_order(self, state: TaskState) -> list[Task]:
        return [state.tasks[task_id] for task_id in self._topological_order(state.tasks)]

    def _topological_order(self, tasks: dict[TaskId, Task]) -> list[TaskId]:
        indegree: dict[TaskId, int] = {task_id: 0 for task_id in tasks}
        dependents: dict[TaskId, list[TaskId]] = defaultdict(list)

        for task_id, task in tasks.items():
            for dependency_id in task.depends_on:
                if dependency_id not in tasks:
                    raise TaskGraphError(f"task {task_id!r} depends on unknown task {dependency_id!r}")
                if dependency_id == task_id:
                    raise TaskGraphError(f"task {task_id!r} cannot depend on itself")
                indegree[task_id] += 1
                dependents[dependency_id].append(task_id)

        ready = deque(sorted(task_id for task_id, degree in indegree.items() if degree == 0))
        order: list[TaskId] = []
        while ready:
            current = ready.popleft()
            order.append(current)
            for dependent in sorted(dependents[current]):
                indegree[dependent] -= 1
                if indegree[dependent] == 0:
                    ready.append(dependent)

        if len(order) != len(tasks):
            raise TaskGraphError("task dependency graph contains a cycle")
        return order

    def _dependencies_completed(self, task: Task, tasks: dict[TaskId, Task]) -> bool:
        return all(tasks[dependency_id].status is TaskStatus.COMPLETED for dependency_id in task.depends_on)

    def _next_task_id(self, existing_ids: Iterable[TaskId]) -> TaskId:
        return self._next_id(existing_ids, prefix="task")

    def _next_attempt_id(self) -> AttemptId:
        self.store.ensure_layout()
        attempt_ids = [Path(path).stem for path in self.store.attempts_dir.glob("*.json")]
        return self._next_id(attempt_ids, prefix="attempt")

    @staticmethod
    def _next_id(existing_ids: Iterable[str], *, prefix: str) -> str:
        max_value = 0
        for existing_id in existing_ids:
            match = _ID_TEMPLATE.match(existing_id)
            if match is None or match.group("prefix") != prefix:
                continue
            max_value = max(max_value, int(match.group("number")))
        return f"{prefix}-{max_value + 1:04d}"

    @staticmethod
    def _replace_task(task: Task, **updates: object) -> Task:
        payload = task.model_dump(mode="python")
        payload.update(updates)
        return Task(**payload)

    @staticmethod
    def _replace_attempt(attempt: TaskAttempt, **updates: object) -> TaskAttempt:
        payload = attempt.model_dump(mode="python")
        payload.update({key: value for key, value in updates.items() if value is not None or key == "finished_at"})
        return TaskAttempt(**payload)


__all__ = [
    "AttemptNotFoundError",
    "AttemptStateError",
    "TaskGraphError",
    "TaskNotFoundError",
    "TaskNotReadyError",
    "TaskService",
    "TaskServiceError",
    "TERMINAL_TASK_STATUSES",
]
