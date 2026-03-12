from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from pydantic import ValidationError

from aftk.tasks import (
    ArtifactKind,
    ArtifactRef,
    Blocker,
    BlockerKind,
    Task,
    TaskAttempt,
    TaskAttemptStatus,
    TaskDraft,
    TaskEvent,
    TaskEventKind,
    TaskGraphError,
    TaskLifecycleError,
    TaskPatch,
    TaskPriority,
    TaskService,
    TaskState,
    TaskStatus,
    TaskStore,
    TaskNotReadyError,
)


def ts(year: int, month: int, day: int, hour: int = 0, minute: int = 0, second: int = 0) -> datetime:
    return datetime(year, month, day, hour, minute, second, tzinfo=timezone.utc)


def make_task(**overrides: object) -> Task:
    data: dict[str, object] = {
        "id": "task-0001",
        "title": "Formalize the demo theorem",
        "description": "Finish the small proof in Demo.lean.",
        "kind": "formalization",
        "status": TaskStatus.READY,
        "priority": TaskPriority.NORMAL,
        "acceptance_criteria": ["`lake build` succeeds"],
        "depends_on": [],
        "blockers": [],
        "scope": [ArtifactRef(kind=ArtifactKind.FILE, value="Demo.lean")],
        "context_summary": "Work locally in Demo.lean.",
        "notes": [],
        "created_by": "initializer",
        "updated_by": "initializer",
        "current_attempt_id": None,
        "attempt_count": 0,
        "created_at": ts(2026, 3, 1),
        "updated_at": ts(2026, 3, 1),
    }
    data.update(overrides)
    return Task(**data)


def make_attempt(**overrides: object) -> TaskAttempt:
    data: dict[str, object] = {
        "id": "attempt-0001",
        "task_id": "task-0001",
        "worker_kind": "worker",
        "status": TaskAttemptStatus.RUNNING,
        "started_at": ts(2026, 3, 1, 12),
        "finished_at": None,
        "run_id": None,
        "report_path": None,
        "transcript_path": None,
        "llm_call_log_path": None,
        "tool_call_log_path": None,
        "usage_summary": None,
        "cost_summary": None,
        "summary": None,
    }
    data.update(overrides)
    return TaskAttempt(**data)


def make_state(*tasks: Task, revision: int = 0) -> TaskState:
    return TaskState(
        revision=revision,
        tasks={task.id: task for task in tasks},
        created_at=ts(2026, 3, 1),
        updated_at=ts(2026, 3, 1),
    )


class TaskModelTests(unittest.TestCase):
    def test_in_progress_task_requires_current_attempt_id(self) -> None:
        with self.assertRaises(ValidationError):
            make_task(status=TaskStatus.IN_PROGRESS)

    def test_blocked_task_requires_a_blocker(self) -> None:
        with self.assertRaises(ValidationError):
            make_task(status=TaskStatus.BLOCKED)

        task = make_task(
            status=TaskStatus.BLOCKED,
            blockers=[Blocker(kind=BlockerKind.INFORMATION, summary="Need a theorem statement")],
        )
        self.assertEqual(task.status, TaskStatus.BLOCKED)

    def test_task_patch_rejects_overlapping_dependency_changes(self) -> None:
        with self.assertRaises(ValidationError):
            TaskPatch(
                task_id="task-0001",
                add_dependencies=["task-0002"],
                remove_dependencies=["task-0002"],
            )

    def test_finished_attempt_requires_finished_at(self) -> None:
        with self.assertRaises(ValidationError):
            make_attempt(status=TaskAttemptStatus.COMPLETED, finished_at=None)

        attempt = make_attempt(
            status=TaskAttemptStatus.COMPLETED,
            finished_at=ts(2026, 3, 1, 12, 5),
            summary="Completed cleanly.",
        )
        self.assertEqual(attempt.status, TaskAttemptStatus.COMPLETED)

    def test_task_state_requires_matching_task_keys(self) -> None:
        with self.assertRaises(ValidationError):
            TaskState(
                revision=1,
                tasks={"task-0002": make_task(id="task-0001")},
                created_at=ts(2026, 3, 1),
                updated_at=ts(2026, 3, 1),
            )


class TaskStoreTests(unittest.TestCase):
    def test_load_or_create_state_initializes_layout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / ".aftk" / "tasks"
            store = TaskStore(root)

            state = store.load_or_create_state()

            self.assertEqual(state, TaskState.empty(now=state.created_at))
            self.assertTrue(store.state_path.is_file())
            self.assertTrue(store.events_path.is_file())
            self.assertTrue(store.attempts_dir.is_dir())

    def test_state_event_and_attempt_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            store = TaskStore(Path(tmp) / ".aftk" / "tasks")
            task = make_task()
            state = TaskState(
                revision=3,
                tasks={task.id: task},
                created_at=ts(2026, 3, 1),
                updated_at=ts(2026, 3, 1, 0, 10),
            )

            store.save_state(state)
            loaded_state = store.load_state()
            self.assertEqual(loaded_state, state)
            self.assertIn('"revision": 3', store.state_path.read_text(encoding="utf-8"))

            event = TaskEvent(
                kind=TaskEventKind.TASK_CREATED,
                revision=3,
                task_id=task.id,
                actor="initializer",
                payload={"title": task.title},
            )
            store.append_event(event)
            self.assertEqual(store.load_events(), [event])

            attempt = make_attempt(
                status=TaskAttemptStatus.COMPLETED,
                finished_at=ts(2026, 3, 1, 12, 7),
                run_id="run-0001",
                summary="Completed cleanly.",
                usage_summary={"requests": 1, "input_tokens": 42},
            )
            store.save_attempt(attempt)
            self.assertEqual(store.load_attempt(attempt.id), attempt)
            self.assertEqual(store.list_attempts(), [attempt])


class TaskServiceTests(unittest.TestCase):
    def test_create_tasks_assigns_ids_and_normalizes_readiness(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = TaskService(Path(tmp) / ".aftk" / "tasks")
            completed = make_task(id="task-0001", status=TaskStatus.COMPLETED)
            service.store.save_state(make_state(completed))

            created = service.create_tasks(
                [
                    TaskDraft(
                        title="Formalize the corollary",
                        description="Use the finished theorem as a dependency.",
                        kind="formalization",
                        depends_on=["task-0001"],
                        acceptance_criteria=["The corollary is proved."],
                        scope=[ArtifactRef(kind=ArtifactKind.FILE, value="Demo.lean")],
                    )
                ],
                actor="initializer",
                now=ts(2026, 3, 1, 1),
            )

            self.assertEqual([task.id for task in created], ["task-0002"])
            self.assertEqual(created[0].status, TaskStatus.READY)
            state = service.load_state()
            self.assertEqual(state.revision, 1)
            self.assertEqual(state.tasks["task-0002"].status, TaskStatus.READY)
            self.assertEqual([event.kind for event in service.store.load_events()], [TaskEventKind.TASK_CREATED])

    def test_graph_invariants_reject_unknown_self_and_cycle_dependencies(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = TaskService(Path(tmp) / ".aftk" / "tasks")
            first = make_task(id="task-0001", status=TaskStatus.READY)
            second = make_task(id="task-0002", status=TaskStatus.PLANNED, depends_on=["task-0001"])
            service.store.save_state(make_state(first, second))

            with self.assertRaises(TaskGraphError):
                service.apply_patch(
                    TaskPatch(task_id="task-0001", add_dependencies=["task-9999"]),
                    actor="orchestrator",
                    now=ts(2026, 3, 1, 2),
                )

            with self.assertRaises(TaskGraphError):
                service.apply_patch(
                    TaskPatch(task_id="task-0001", add_dependencies=["task-0001"]),
                    actor="orchestrator",
                    now=ts(2026, 3, 1, 2, 1),
                )

            with self.assertRaises(TaskGraphError):
                service.apply_patch(
                    TaskPatch(task_id="task-0001", add_dependencies=["task-0002"]),
                    actor="orchestrator",
                    now=ts(2026, 3, 1, 2, 2),
                )

    def test_patch_recomputes_readiness_for_dependents(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = TaskService(Path(tmp) / ".aftk" / "tasks")
            first = make_task(id="task-0001", status=TaskStatus.READY)
            second = make_task(id="task-0002", status=TaskStatus.PLANNED, depends_on=["task-0001"])
            service.store.save_state(make_state(first, second))

            patched = service.apply_patch(
                TaskPatch(task_id="task-0001", new_status=TaskStatus.COMPLETED),
                actor="orchestrator",
                now=ts(2026, 3, 1, 3),
            )

            self.assertEqual(patched.status, TaskStatus.COMPLETED)
            state = service.load_state()
            self.assertEqual(state.revision, 1)
            self.assertEqual(state.tasks["task-0002"].status, TaskStatus.READY)

            events = service.store.load_events()
            self.assertEqual([event.task_id for event in events], ["task-0001", "task-0002"])
            self.assertEqual(events[1].payload["reason"], "readiness_recomputed")
            self.assertEqual(events[1].payload["new_status"], TaskStatus.READY.value)

    def test_claim_task_creates_attempt_and_rejects_terminal_task(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = TaskService(Path(tmp) / ".aftk" / "tasks")
            ready = make_task(id="task-0001", status=TaskStatus.READY)
            completed = make_task(id="task-0002", status=TaskStatus.COMPLETED)
            service.store.save_state(make_state(ready, completed))

            attempt = service.claim_task(
                "task-0001",
                actor="runner",
                worker_kind="worker",
                now=ts(2026, 3, 1, 4),
            )

            state = service.load_state()
            claimed = state.tasks["task-0001"]
            self.assertEqual(attempt.id, "attempt-0001")
            self.assertEqual(claimed.status, TaskStatus.IN_PROGRESS)
            self.assertEqual(claimed.current_attempt_id, attempt.id)
            self.assertEqual(claimed.attempt_count, 1)
            self.assertEqual(service.list_ready_tasks(), [])

            with self.assertRaises(TaskNotReadyError):
                service.claim_task(
                    "task-0002",
                    actor="runner",
                    worker_kind="worker",
                    now=ts(2026, 3, 1, 4, 1),
                )

    def test_reconcile_finished_attempt_marks_completed_task_and_clears_active_attempt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = TaskService(Path(tmp) / ".aftk" / "tasks")
            service.store.save_state(make_state(make_task(id="task-0001", status=TaskStatus.READY)))

            attempt = service.claim_task(
                "task-0001",
                actor="runner",
                worker_kind="worker",
                now=ts(2026, 3, 1, 5),
            )
            finished_attempt = service.finish_attempt(
                attempt.id,
                actor="runner",
                status=TaskAttemptStatus.COMPLETED,
                summary="The worker finished successfully.",
                run_id="run-0001",
                now=ts(2026, 3, 1, 5, 10),
            )

            reconciled_task = service.reconcile_finished_attempt(
                attempt.id,
                actor="runner",
                now=ts(2026, 3, 1, 5, 11),
            )

            self.assertEqual(finished_attempt.status, TaskAttemptStatus.COMPLETED)
            self.assertEqual(service.store.load_attempt(attempt.id), finished_attempt)
            self.assertEqual(reconciled_task.status, TaskStatus.COMPLETED)
            self.assertIsNone(reconciled_task.current_attempt_id)
            self.assertEqual(reconciled_task.notes[-1].message, "The worker finished successfully.")

            state_after_reconcile = service.load_state()
            self.assertEqual(state_after_reconcile.tasks["task-0001"].status, TaskStatus.COMPLETED)
            self.assertIsNone(state_after_reconcile.tasks["task-0001"].current_attempt_id)

            reconciliation_event = service.store.load_events()[-1]
            self.assertEqual(reconciliation_event.kind, TaskEventKind.TASK_PATCHED)
            self.assertEqual(reconciliation_event.payload["reason"], "attempt_reconciled")
            self.assertEqual(reconciliation_event.payload["attempt_status"], TaskAttemptStatus.COMPLETED.value)
            self.assertEqual(reconciliation_event.payload["new_status"], TaskStatus.COMPLETED.value)

    def test_reconcile_finished_attempt_requeues_partial_task_as_ready(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = TaskService(Path(tmp) / ".aftk" / "tasks")
            service.store.save_state(make_state(make_task(id="task-0001", status=TaskStatus.READY)))

            attempt = service.claim_task(
                "task-0001",
                actor="runner",
                worker_kind="worker",
                now=ts(2026, 3, 1, 5),
            )
            service.finish_attempt(
                attempt.id,
                actor="runner",
                status=TaskAttemptStatus.PARTIAL,
                summary="The worker made partial progress.",
                run_id="run-0001",
                now=ts(2026, 3, 1, 5, 10),
            )

            reconciled_task = service.reconcile_finished_attempt(
                attempt.id,
                actor="runner",
                now=ts(2026, 3, 1, 5, 11),
            )

            self.assertEqual(reconciled_task.status, TaskStatus.READY)
            self.assertIsNone(reconciled_task.current_attempt_id)
            self.assertEqual(reconciled_task.notes[-1].message, "The worker made partial progress.")
            self.assertEqual([task.id for task in service.list_ready_tasks()], ["task-0001"])

    def test_reconcile_finished_attempt_marks_blocked_task_and_persists_blockers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = TaskService(Path(tmp) / ".aftk" / "tasks")
            service.store.save_state(make_state(make_task(id="task-0001", status=TaskStatus.READY)))

            attempt = service.claim_task(
                "task-0001",
                actor="runner",
                worker_kind="worker",
                now=ts(2026, 3, 1, 5),
            )
            service.finish_attempt(
                attempt.id,
                actor="runner",
                status=TaskAttemptStatus.BLOCKED,
                summary="Need a missing theorem from the source paper.",
                run_id="run-0001",
                now=ts(2026, 3, 1, 5, 10),
            )

            blockers = [Blocker(kind=BlockerKind.INFORMATION, summary="Need the missing theorem statement.")]
            reconciled_task = service.reconcile_finished_attempt(
                attempt.id,
                actor="runner",
                blockers=blockers,
                now=ts(2026, 3, 1, 5, 11),
            )

            self.assertEqual(reconciled_task.status, TaskStatus.BLOCKED)
            self.assertIsNone(reconciled_task.current_attempt_id)
            self.assertEqual(reconciled_task.blockers, blockers)
            self.assertEqual(reconciled_task.notes[-1].message, "Need a missing theorem from the source paper.")

    def test_reconcile_finished_attempt_marks_failed_task(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = TaskService(Path(tmp) / ".aftk" / "tasks")
            service.store.save_state(make_state(make_task(id="task-0001", status=TaskStatus.READY)))

            attempt = service.claim_task(
                "task-0001",
                actor="runner",
                worker_kind="worker",
                now=ts(2026, 3, 1, 5),
            )
            service.finish_attempt(
                attempt.id,
                actor="runner",
                status=TaskAttemptStatus.FAILED,
                summary="The worker crashed while editing the file.",
                run_id="run-0001",
                now=ts(2026, 3, 1, 5, 10),
            )

            reconciled_task = service.reconcile_finished_attempt(
                attempt.id,
                actor="runner",
                now=ts(2026, 3, 1, 5, 11),
            )

            self.assertEqual(reconciled_task.status, TaskStatus.FAILED)
            self.assertIsNone(reconciled_task.current_attempt_id)
            self.assertEqual(reconciled_task.notes[-1].message, "The worker crashed while editing the file.")

    def test_recover_interrupted_task_requeues_it_on_restart(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / ".aftk" / "tasks"
            service = TaskService(root)
            service.store.save_state(make_state(make_task(id="task-0001", status=TaskStatus.READY)))

            first_attempt = service.claim_task(
                "task-0001",
                actor="runner",
                worker_kind="worker",
                now=ts(2026, 3, 1, 6),
            )

            restarted_service = TaskService(root)
            recovered = restarted_service.recover_interrupted_tasks(actor="system", now=ts(2026, 3, 1, 6, 5))

            self.assertEqual([task.id for task in recovered], ["task-0001"])
            self.assertEqual(recovered[0].status, TaskStatus.READY)
            self.assertIsNone(recovered[0].current_attempt_id)

            recovered_state = restarted_service.load_state()
            self.assertEqual(recovered_state.revision, 2)
            self.assertEqual(recovered_state.tasks["task-0001"].status, TaskStatus.READY)
            self.assertEqual(recovered_state.tasks["task-0001"].attempt_count, 1)
            self.assertEqual(restarted_service.store.load_attempt(first_attempt.id).status, TaskAttemptStatus.RUNNING)

            recovery_event = restarted_service.store.load_events()[-1]
            self.assertEqual(recovery_event.kind, TaskEventKind.TASK_RECOVERED)
            self.assertEqual(recovery_event.attempt_id, first_attempt.id)
            self.assertEqual(recovery_event.payload["attempt_status"], TaskAttemptStatus.RUNNING.value)
            self.assertEqual(recovery_event.payload["new_status"], TaskStatus.READY.value)

            second_attempt = restarted_service.claim_task(
                "task-0001",
                actor="runner",
                worker_kind="worker",
                now=ts(2026, 3, 1, 6, 10),
            )
            self.assertEqual(second_attempt.id, "attempt-0002")
            self.assertEqual(restarted_service.load_state().tasks["task-0001"].attempt_count, 2)

    def test_recovery_reconciles_finished_attempts_left_in_progress(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = TaskService(Path(tmp) / ".aftk" / "tasks")
            task = make_task(
                id="task-0001",
                status=TaskStatus.IN_PROGRESS,
                current_attempt_id="attempt-0001",
                attempt_count=1,
            )
            service.store.save_state(make_state(task))
            service.store.save_attempt(
                make_attempt(
                    id="attempt-0001",
                    status=TaskAttemptStatus.PARTIAL,
                    finished_at=ts(2026, 3, 1, 12, 5),
                    summary="Partial proof work is complete.",
                )
            )

            recovered = service.recover_interrupted_tasks(actor="system", now=ts(2026, 3, 1, 6, 10))

            self.assertEqual([task.id for task in recovered], ["task-0001"])
            self.assertEqual(recovered[0].status, TaskStatus.READY)
            self.assertIsNone(recovered[0].current_attempt_id)
            self.assertEqual(recovered[0].notes[-1].message, "Partial proof work is complete.")

            recovery_event = service.store.load_events()[-1]
            self.assertEqual(recovery_event.kind, TaskEventKind.TASK_RECOVERED)
            self.assertEqual(recovery_event.payload["reason"], "finished_attempt_reconciled")
            self.assertTrue(recovery_event.payload["attempt_record_found"])
            self.assertEqual(recovery_event.payload["attempt_status"], TaskAttemptStatus.PARTIAL.value)
            self.assertEqual(recovery_event.payload["new_status"], TaskStatus.READY.value)

    def test_validate_runtime_state_rejects_finished_current_attempt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = TaskService(Path(tmp) / ".aftk" / "tasks")
            task = make_task(
                id="task-0001",
                status=TaskStatus.IN_PROGRESS,
                current_attempt_id="attempt-0001",
                attempt_count=1,
            )
            service.store.save_state(make_state(task))
            service.store.save_attempt(
                make_attempt(
                    id="attempt-0001",
                    status=TaskAttemptStatus.COMPLETED,
                    finished_at=ts(2026, 3, 1, 12, 5),
                    summary="Finished.",
                )
            )

            with self.assertRaises(TaskLifecycleError):
                service.validate_runtime_state()

    def test_recovery_tolerates_missing_attempt_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = TaskService(Path(tmp) / ".aftk" / "tasks")
            service.store.save_state(
                make_state(
                    make_task(
                        id="task-0001",
                        status=TaskStatus.IN_PROGRESS,
                        current_attempt_id="attempt-9999",
                    )
                )
            )

            recovered = service.recover_interrupted_tasks(actor="system", now=ts(2026, 3, 1, 7))

            self.assertEqual([task.id for task in recovered], ["task-0001"])
            self.assertEqual(service.load_state().tasks["task-0001"].status, TaskStatus.READY)

            recovery_event = service.store.load_events()[-1]
            self.assertEqual(recovery_event.kind, TaskEventKind.TASK_RECOVERED)
            self.assertFalse(recovery_event.payload["attempt_record_found"])
            self.assertIsNone(recovery_event.payload["attempt_status"])


if __name__ == "__main__":
    unittest.main()
