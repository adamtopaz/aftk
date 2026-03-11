from __future__ import annotations

from collections.abc import Callable
from pathlib import Path
from typing import Any

from pydantic import Field
from pydantic_ai import FunctionToolset

from aftk.coding.models import FileReadResult, ProjectPath
from aftk.config import FrameworkModel
from aftk.project import ProjectSnapshot, RelativeProjectPath


class ProjectSnapshotSummary(FrameworkModel):
    project_root: str
    generated_state_dir: RelativeProjectPath
    entrypoint_path: RelativeProjectPath
    lakefile_path: RelativeProjectPath
    sources_present: bool
    source_file_count: int = Field(ge=0)
    source_paths: list[RelativeProjectPath] = Field(default_factory=list)
    lean_file_count: int = Field(ge=0)
    lean_file_paths: list[RelativeProjectPath] = Field(default_factory=list)


class ProjectContextTools:
    def __init__(self, snapshot: ProjectSnapshot) -> None:
        self.snapshot = snapshot
        self.project_root = Path(snapshot.project_root).expanduser().resolve(strict=False)
        self.entrypoint_path = (self.project_root / snapshot.entrypoint_path).resolve(strict=False)
        self.sources_dir = (self.project_root / snapshot.sources_dir).resolve(strict=False)
        self._source_paths = {record.path for record in snapshot.source_inventory}

    def get_project_snapshot_summary(self) -> ProjectSnapshotSummary:
        """Return a compact summary of the persisted project snapshot for planning prompts."""
        return ProjectSnapshotSummary(
            project_root=self.snapshot.project_root,
            generated_state_dir=self.snapshot.generated_state_dir,
            entrypoint_path=self.snapshot.entrypoint_path,
            lakefile_path=self.snapshot.lakefile_path,
            sources_present=self.snapshot.sources_present,
            source_file_count=len(self.snapshot.source_inventory),
            source_paths=[record.path for record in self.snapshot.source_inventory],
            lean_file_count=len(self.snapshot.lean_files),
            lean_file_paths=[record.path for record in self.snapshot.lean_files],
        )

    def read_entrypoint(self) -> FileReadResult:
        """Read the human-authored entrypoint brief from entrypoint.md."""
        return FileReadResult(path=self.snapshot.entrypoint_path, content=self._read_text(self.entrypoint_path))

    def list_source_files(self, limit: int = 200) -> list[ProjectPath]:
        """List source-material files captured in the project snapshot."""
        if limit < 1:
            raise ValueError("limit must be at least 1")
        return [ProjectPath(path=record.path) for record in self.snapshot.source_inventory[:limit]]

    def read_source_file(self, path: str) -> FileReadResult:
        """Read a UTF-8 source-material file that is present in the project snapshot inventory."""
        resolved = self._resolve_project_path(path)
        relative = self._relative_path(resolved)
        if relative not in self._source_paths:
            raise ValueError(f"path is not part of the source inventory: {relative}")
        return FileReadResult(path=relative, content=self._read_text(resolved))

    def list_lean_files(self, limit: int = 200) -> list[ProjectPath]:
        """List Lean source files discovered by the deterministic project snapshot."""
        if limit < 1:
            raise ValueError("limit must be at least 1")
        return [ProjectPath(path=record.path) for record in self.snapshot.lean_files[:limit]]

    def tool_functions(self) -> tuple[Callable[..., object], ...]:
        return (
            self.get_project_snapshot_summary,
            self.read_entrypoint,
            self.list_source_files,
            self.read_source_file,
            self.list_lean_files,
        )

    def _resolve_project_path(self, path: str) -> Path:
        candidate = Path(path).expanduser()
        if not candidate.is_absolute():
            candidate = self.project_root / candidate
        resolved = candidate.resolve(strict=False)
        try:
            resolved.relative_to(self.project_root)
        except ValueError as exc:
            raise ValueError(f"path {resolved} is not inside project_root {self.project_root}") from exc
        return resolved

    def _relative_path(self, path: Path) -> RelativeProjectPath:
        relative = path.relative_to(self.project_root).as_posix()
        return "." if not relative else relative

    @staticmethod
    def _read_text(path: Path) -> str:
        try:
            return path.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            raise ValueError(f"file is not valid UTF-8 text: {path}") from exc


def build_project_context_toolset(snapshot: ProjectSnapshot) -> Any:
    tools = ProjectContextTools(snapshot)
    return FunctionToolset(tools=list(tools.tool_functions()))


__all__ = [
    "ProjectContextTools",
    "ProjectSnapshotSummary",
    "build_project_context_toolset",
]
