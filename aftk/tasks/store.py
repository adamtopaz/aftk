from __future__ import annotations

import os
from pathlib import Path
from typing import Protocol
from uuid import uuid4

from aftk.tasks.models import TaskRunState


class TaskRunStore(Protocol):
    def exists(self) -> bool: ...

    def load(self) -> TaskRunState: ...

    def save(self, state: TaskRunState) -> None: ...


class InMemoryTaskRunStore:
    def __init__(self, initial_state: TaskRunState | None = None) -> None:
        self._payload: str | None = None
        if initial_state is not None:
            self.save(initial_state)

    def exists(self) -> bool:
        return self._payload is not None

    def load(self) -> TaskRunState:
        if self._payload is None:
            raise FileNotFoundError("in-memory task store is empty")
        return TaskRunState.model_validate_json(self._payload)

    def save(self, state: TaskRunState) -> None:
        self._payload = state.model_dump_json(indent=2, exclude_none=True)


class FileTaskRunStore:
    def __init__(self, path: str | Path) -> None:
        self._path = Path(path)

    @property
    def path(self) -> Path:
        return self._path

    def exists(self) -> bool:
        return self._path.is_file()

    def load(self) -> TaskRunState:
        return TaskRunState.model_validate_json(self._path.read_text(encoding="utf-8"))

    def save(self, state: TaskRunState) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        payload = state.model_dump_json(indent=2, exclude_none=True) + "\n"
        temp_path = self._path.with_name(f".{self._path.name}.{uuid4().hex}.tmp")
        temp_path.write_text(payload, encoding="utf-8")
        os.replace(temp_path, self._path)
