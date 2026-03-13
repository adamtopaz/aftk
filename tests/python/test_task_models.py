from __future__ import annotations

import unittest

from pydantic import ValidationError

from aftk.tasks.models import (
    TaskAttempt,
    TaskAttemptStatus,
    TaskExecutionResult,
    TaskExecutionStatus,
    TaskRecord,
    TaskRunState,
    TaskSpec,
)


class TaskModelTests(unittest.TestCase):
    def test_task_spec_rejects_duplicate_dependencies(self) -> None:
        with self.assertRaises(ValidationError):
            TaskSpec(
                id="task-1",
                kind="formalize_reference",
                title="Formalize group.basic.definition",
                depends_on=["task-0", "task-0"],
            )

    def test_finished_attempts_require_finished_at(self) -> None:
        with self.assertRaises(ValidationError):
            TaskAttempt(
                attempt=1,
                status=TaskAttemptStatus.completed,
            )

    def test_failed_execution_requires_error_message(self) -> None:
        with self.assertRaises(ValidationError):
            TaskExecutionResult(status=TaskExecutionStatus.failed)

    def test_task_run_state_round_trips(self) -> None:
        record = TaskRecord(
            id="task-1",
            kind="formalize_reference",
            title="Formalize group.basic.definition",
            payload={"ref": "group.basic.definition"},
        )
        state = TaskRunState(run_id="run-1", tasks={record.id: record})

        decoded = TaskRunState.model_validate_json(state.model_dump_json())

        self.assertEqual(decoded.run_id, "run-1")
        self.assertEqual(decoded.tasks["task-1"].payload["ref"], "group.basic.definition")


if __name__ == "__main__":
    unittest.main()
