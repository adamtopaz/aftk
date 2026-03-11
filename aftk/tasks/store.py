from __future__ import annotations

import os
from pathlib import Path
from tempfile import NamedTemporaryFile

from pydantic import BaseModel

from aftk.tasks.models import AttemptId, TaskAttempt, TaskEvent, TaskState


PathLike = str | os.PathLike[str]


class TaskStore:
    STATE_FILE_NAME = "state.json"
    EVENTS_FILE_NAME = "events.jsonl"
    ATTEMPTS_DIR_NAME = "attempts"

    def __init__(self, root: PathLike) -> None:
        self.root = Path(root).expanduser().resolve(strict=False)
        self.state_path = self.root / self.STATE_FILE_NAME
        self.events_path = self.root / self.EVENTS_FILE_NAME
        self.attempts_dir = self.root / self.ATTEMPTS_DIR_NAME

    def ensure_layout(self) -> None:
        self.root.mkdir(parents=True, exist_ok=True)
        self.attempts_dir.mkdir(parents=True, exist_ok=True)
        self.events_path.touch(exist_ok=True)

    def has_state(self) -> bool:
        return self.state_path.is_file()

    def load_or_create_state(self) -> TaskState:
        self.ensure_layout()
        if self.has_state():
            return self.load_state()
        state = TaskState.empty()
        self.save_state(state)
        return state

    def load_state(self) -> TaskState:
        return TaskState.model_validate_json(self.state_path.read_text(encoding="utf-8"))

    def save_state(self, state: TaskState) -> Path:
        self.ensure_layout()
        self._write_model_json(self.state_path, state, indent=2)
        return self.state_path

    def append_event(self, event: TaskEvent) -> Path:
        self.ensure_layout()
        with self.events_path.open("a", encoding="utf-8") as handle:
            handle.write(event.model_dump_json())
            handle.write("\n")
        return self.events_path

    def load_events(self) -> list[TaskEvent]:
        if not self.events_path.exists():
            return []
        events: list[TaskEvent] = []
        with self.events_path.open("r", encoding="utf-8") as handle:
            for line in handle:
                payload = line.strip()
                if not payload:
                    continue
                events.append(TaskEvent.model_validate_json(payload))
        return events

    def save_attempt(self, attempt: TaskAttempt) -> Path:
        self.ensure_layout()
        path = self.attempt_path(attempt.id)
        self._write_model_json(path, attempt, indent=2)
        return path

    def load_attempt(self, attempt_id: AttemptId) -> TaskAttempt:
        return TaskAttempt.model_validate_json(self.attempt_path(attempt_id).read_text(encoding="utf-8"))

    def list_attempts(self) -> list[TaskAttempt]:
        if not self.attempts_dir.exists():
            return []
        return [
            TaskAttempt.model_validate_json(path.read_text(encoding="utf-8"))
            for path in sorted(self.attempts_dir.glob("*.json"))
        ]

    def attempt_path(self, attempt_id: AttemptId) -> Path:
        return self.attempts_dir / f"{attempt_id}.json"

    @staticmethod
    def _write_model_json(path: Path, model: BaseModel, *, indent: int | None = None) -> None:
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


__all__ = ["TaskStore"]
