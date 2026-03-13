from __future__ import annotations

import unittest

from aftk.tasks.manager import TaskConflictError, TaskManager, TaskTransitionError
from aftk.tasks.models import TaskArtifact, TaskLifecycleStatus, TaskSpec
from aftk.tasks.store import InMemoryTaskRunStore


class TaskManagerTests(unittest.TestCase):
    def test_add_tasks_claim_complete_and_persist_attempts(self) -> None:
        store = InMemoryTaskRunStore()
        manager = TaskManager.create(store, "run-1")
        manager.add_tasks(
            [
                TaskSpec(id="task-1", kind="seed", title="Task 1"),
                TaskSpec(id="task-2", kind="seed", title="Task 2", depends_on=["task-1"]),
            ]
        )

        claimed = manager.claim_task("task-1", runner_id="agent-1")
        self.assertEqual(claimed.status, TaskLifecycleStatus.running)
        self.assertEqual(claimed.attempts[-1].runner_id, "agent-1")

        completed = manager.complete_task(
            "task-1",
            summary="done",
            artifacts=[TaskArtifact(kind="output", value="hello")],
        )
        self.assertEqual(completed.status, TaskLifecycleStatus.completed)
        self.assertEqual(completed.attempts[-1].summary, "done")
        self.assertEqual(completed.artifacts[-1].value, "hello")
        self.assertEqual(manager.scheduler_status("task-2").value, "ready")

        reloaded = TaskManager.load(store)
        self.assertEqual(reloaded.get_task("task-1").status, TaskLifecycleStatus.completed)
        self.assertEqual(reloaded.ready_tasks()[0].id, "task-2")

    def test_claim_rejects_blocked_tasks(self) -> None:
        manager = TaskManager.create(InMemoryTaskRunStore(), "run-1")
        manager.add_tasks(
            [
                TaskSpec(id="task-1", kind="seed", title="Task 1"),
                TaskSpec(id="task-2", kind="seed", title="Task 2", depends_on=["task-1"]),
            ]
        )

        with self.assertRaises(TaskTransitionError):
            manager.claim_task("task-2")

    def test_add_tasks_rejects_duplicate_ids_in_one_batch(self) -> None:
        manager = TaskManager.create(InMemoryTaskRunStore(), "run-1")

        with self.assertRaises(TaskConflictError):
            manager.add_tasks(
                [
                    TaskSpec(id="task-1", kind="seed", title="Task 1"),
                    TaskSpec(id="task-1", kind="seed", title="Duplicate Task 1"),
                ]
            )

    def test_failed_task_can_be_requeued_until_max_attempts(self) -> None:
        manager = TaskManager.create(InMemoryTaskRunStore(), "run-1")
        manager.add_task(TaskSpec(id="task-1", kind="seed", title="Task 1", max_attempts=2))

        manager.claim_task("task-1")
        failed = manager.fail_task("task-1", error_message="boom")
        self.assertEqual(failed.status, TaskLifecycleStatus.failed)
        self.assertEqual(failed.last_error, "boom")

        pending = manager.requeue_task("task-1")
        self.assertEqual(pending.status, TaskLifecycleStatus.pending)
        self.assertIsNone(pending.last_error)

        manager.claim_task("task-1")
        manager.fail_task("task-1", error_message="boom again")
        with self.assertRaises(TaskTransitionError):
            manager.requeue_task("task-1")


if __name__ == "__main__":
    unittest.main()
