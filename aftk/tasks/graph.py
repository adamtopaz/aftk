from __future__ import annotations

from collections.abc import Mapping

from aftk.tasks.models import TaskLifecycleStatus, TaskRecord, TaskSchedulerStatus


class TaskGraphError(ValueError):
    """Base error raised for invalid task graphs."""


class MissingDependencyError(TaskGraphError):
    """Raised when a task references a dependency id that does not exist."""


class TaskCycleError(TaskGraphError):
    """Raised when task dependencies contain a cycle."""


class TaskMappingError(TaskGraphError):
    """Raised when the mapping key for a task does not match the task id."""


StatusMap = Mapping[str, TaskRecord]


def validate_task_graph(tasks: StatusMap) -> None:
    for task_id, task in tasks.items():
        if task.id != task_id:
            raise TaskMappingError(f"task mapping key {task_id!r} does not match task id {task.id!r}")
        for dependency_id in task.depends_on:
            if dependency_id not in tasks:
                raise MissingDependencyError(
                    f"task {task_id!r} depends on missing task {dependency_id!r}"
                )

    visit_state: dict[str, int] = {}
    stack: list[str] = []

    def visit(task_id: str) -> None:
        state = visit_state.get(task_id, 0)
        if state == 1:
            if task_id in stack:
                start = stack.index(task_id)
                cycle = stack[start:] + [task_id]
            else:
                cycle = [task_id, task_id]
            rendered = " -> ".join(cycle)
            raise TaskCycleError(f"cycle detected: {rendered}")
        if state == 2:
            return

        visit_state[task_id] = 1
        stack.append(task_id)
        for dependency_id in tasks[task_id].depends_on:
            visit(dependency_id)
        stack.pop()
        visit_state[task_id] = 2

    for task_id in tasks:
        visit(task_id)


def scheduler_status(task: TaskRecord, tasks: StatusMap) -> TaskSchedulerStatus:
    if task.status == TaskLifecycleStatus.running:
        return TaskSchedulerStatus.running
    if task.status == TaskLifecycleStatus.completed:
        return TaskSchedulerStatus.completed
    if task.status == TaskLifecycleStatus.failed:
        return TaskSchedulerStatus.failed
    if task.status == TaskLifecycleStatus.canceled:
        return TaskSchedulerStatus.canceled

    if all(tasks[dependency_id].status == TaskLifecycleStatus.completed for dependency_id in task.depends_on):
        return TaskSchedulerStatus.ready
    return TaskSchedulerStatus.blocked


def is_ready(task: TaskRecord, tasks: StatusMap) -> bool:
    return scheduler_status(task, tasks) == TaskSchedulerStatus.ready


def is_terminal(task: TaskRecord) -> bool:
    return task.status in {
        TaskLifecycleStatus.completed,
        TaskLifecycleStatus.failed,
        TaskLifecycleStatus.canceled,
    }


def dependency_tasks(task: TaskRecord, tasks: StatusMap) -> list[TaskRecord]:
    return [tasks[dependency_id] for dependency_id in task.depends_on]


def ready_tasks(tasks: StatusMap) -> list[TaskRecord]:
    return _sorted([task for task in tasks.values() if is_ready(task, tasks)])


def blocked_tasks(tasks: StatusMap) -> list[TaskRecord]:
    return _sorted([task for task in tasks.values() if scheduler_status(task, tasks) == TaskSchedulerStatus.blocked])


def incomplete_tasks(tasks: StatusMap) -> list[TaskRecord]:
    return _sorted([task for task in tasks.values() if not is_terminal(task)])


def terminal_tasks(tasks: StatusMap) -> list[TaskRecord]:
    return _sorted([task for task in tasks.values() if is_terminal(task)])


def _sorted(tasks: list[TaskRecord]) -> list[TaskRecord]:
    return sorted(tasks, key=lambda task: (-task.priority, task.id))
