from __future__ import annotations

import unittest

from aftk.tasks.graph import (
    MissingDependencyError,
    TaskCycleError,
    blocked_tasks,
    ready_tasks,
    scheduler_status,
    validate_task_graph,
)
from aftk.tasks.models import TaskLifecycleStatus, TaskRecord, TaskSchedulerStatus, utc_now


class TaskGraphTests(unittest.TestCase):
    def test_validate_rejects_missing_dependencies(self) -> None:
        tasks = {
            "task-1": TaskRecord(
                id="task-1",
                kind="formalize_reference",
                title="Task 1",
                depends_on=["task-0"],
            )
        }

        with self.assertRaises(MissingDependencyError):
            validate_task_graph(tasks)

    def test_validate_rejects_cycles(self) -> None:
        tasks = {
            "task-1": TaskRecord(
                id="task-1",
                kind="formalize_reference",
                title="Task 1",
                depends_on=["task-2"],
            ),
            "task-2": TaskRecord(
                id="task-2",
                kind="formalize_reference",
                title="Task 2",
                depends_on=["task-1"],
            ),
        }

        with self.assertRaises(TaskCycleError):
            validate_task_graph(tasks)

    def test_ready_and_blocked_statuses_are_derived_from_dependencies(self) -> None:
        finished_at = utc_now()
        tasks = {
            "task-1": TaskRecord(
                id="task-1",
                kind="formalize_reference",
                title="Task 1",
                status=TaskLifecycleStatus.completed,
                started_at=finished_at,
                finished_at=finished_at,
            ),
            "task-2": TaskRecord(
                id="task-2",
                kind="formalize_reference",
                title="Task 2",
                depends_on=["task-1"],
            ),
            "task-3": TaskRecord(
                id="task-3",
                kind="formalize_reference",
                title="Task 3",
                depends_on=["task-2"],
            ),
        }

        validate_task_graph(tasks)

        self.assertEqual(scheduler_status(tasks["task-2"], tasks), TaskSchedulerStatus.ready)
        self.assertEqual(scheduler_status(tasks["task-3"], tasks), TaskSchedulerStatus.blocked)
        self.assertEqual([task.id for task in ready_tasks(tasks)], ["task-2"])
        self.assertEqual([task.id for task in blocked_tasks(tasks)], ["task-3"])


if __name__ == "__main__":
    unittest.main()
