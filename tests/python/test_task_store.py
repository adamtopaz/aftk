from __future__ import annotations

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from aftk.tasks.models import TaskRecord, TaskRunState
from aftk.tasks.store import FileTaskRunStore


class TaskStoreTests(unittest.TestCase):
    def test_file_store_round_trips_state(self) -> None:
        with TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "state.json"
            store = FileTaskRunStore(path)
            task = TaskRecord(
                id="task-1",
                kind="formalize_reference",
                title="Formalize group.basic.definition",
                payload={"ref": "group.basic.definition"},
            )
            state = TaskRunState(run_id="run-1", tasks={task.id: task})

            store.save(state)
            loaded = store.load()

            self.assertTrue(store.exists())
            self.assertEqual(loaded.run_id, "run-1")
            self.assertEqual(loaded.tasks[task.id].payload["ref"], "group.basic.definition")


if __name__ == "__main__":
    unittest.main()
