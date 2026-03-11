from __future__ import annotations

import os
from datetime import datetime
from pathlib import Path

from aftk.config import FrameworkConfig, FrameworkPaths
from aftk.coding.models import CodingAction, CodingActionKind, RelativeCodingPath, utc_now


PathLike = str | os.PathLike[str]


class CodingActionLogStore:
    FILE_NAME = "coding-actions.jsonl"

    def __init__(self, runs_root: PathLike, run_id: str) -> None:
        if not run_id:
            raise ValueError("run_id must not be empty")
        self.runs_root = Path(runs_root).expanduser().resolve(strict=False)
        self.run_id = run_id
        self.run_dir = self.runs_root / run_id
        self.path = self.run_dir / self.FILE_NAME

    def ensure_layout(self) -> None:
        self.run_dir.mkdir(parents=True, exist_ok=True)

    def append(self, action: CodingAction) -> Path:
        self.ensure_layout()
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(action.model_dump_json())
            handle.write("\n")
        return self.path

    def load_actions(self) -> list[CodingAction]:
        if not self.path.exists():
            return []
        actions: list[CodingAction] = []
        with self.path.open("r", encoding="utf-8") as handle:
            for line in handle:
                payload = line.strip()
                if not payload:
                    continue
                actions.append(CodingAction.model_validate_json(payload))
        return actions


class CodingActionRecorder:
    def __init__(
        self,
        store: CodingActionLogStore,
        *,
        task_id: str | None = None,
        attempt_id: str | None = None,
    ) -> None:
        self.store = store
        self.task_id = task_id
        self.attempt_id = attempt_id

    @classmethod
    def for_project(
        cls,
        project: FrameworkConfig | FrameworkPaths | PathLike,
        *,
        run_id: str,
        task_id: str | None = None,
        attempt_id: str | None = None,
    ) -> CodingActionRecorder:
        runs_root = _resolve_runs_root(project)
        return cls(
            CodingActionLogStore(runs_root, run_id),
            task_id=task_id,
            attempt_id=attempt_id,
        )

    def record(
        self,
        kind: CodingActionKind,
        *,
        path: RelativeCodingPath | None = None,
        argv: list[str] | None = None,
        details: dict[str, object] | None = None,
        now: datetime | None = None,
    ) -> CodingAction:
        action = CodingAction(
            kind=kind,
            run_id=self.store.run_id,
            task_id=self.task_id,
            attempt_id=self.attempt_id,
            timestamp=utc_now() if now is None else now,
            path=path,
            argv=None if argv is None else list(argv),
            details={} if details is None else dict(details),
        )
        self.store.append(action)
        return action


def _resolve_runs_root(project: FrameworkConfig | FrameworkPaths | PathLike) -> Path:
    if isinstance(project, FrameworkConfig):
        return project.paths.runs_dir
    if isinstance(project, FrameworkPaths):
        return project.runs_dir
    root = Path(project).expanduser().resolve(strict=False)
    return (root / ".aftk" / "runs").resolve(strict=False)


__all__ = ["CodingActionLogStore", "CodingActionRecorder", "PathLike"]
