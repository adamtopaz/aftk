from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from pathlib import Path
from tempfile import NamedTemporaryFile

from aftk.config import FrameworkConfig, FrameworkPaths
from aftk.coding.logs import CodingActionRecorder
from aftk.logging import log_event
from aftk.coding.models import (
    CodingActionKind,
    FileEditResult,
    FileReadResult,
    FileWriteResult,
    RelativeCodingPath,
)


LOGGER = logging.getLogger("aftk.coding")


PathLike = str | os.PathLike[str]
_RESERVED_ROOT_DIR_NAMES = frozenset({".aftk"})
_EXCLUDED_SEARCH_DIR_NAMES = frozenset({".aftk", ".git", ".lake", "__pycache__"})


class CodingError(RuntimeError):
    """Base exception for worker coding-service failures."""


class CodingSandboxError(CodingError):
    """Raised when a requested path escapes the project root."""


class CodingPermissionError(CodingError):
    """Raised when a worker attempts to access a reserved framework path."""


class EditConflictError(CodingError):
    """Raised when a structured text edit cannot be applied safely."""


@dataclass(frozen=True, slots=True)
class _SandboxContext:
    project_root: Path
    runs_dir: Path


class ProjectSandbox:
    reserved_root_dir_names = _RESERVED_ROOT_DIR_NAMES
    excluded_search_dir_names = _EXCLUDED_SEARCH_DIR_NAMES

    def __init__(
        self,
        project: FrameworkConfig | FrameworkPaths | PathLike,
        *,
        recorder: CodingActionRecorder | None = None,
    ) -> None:
        context = _resolve_context(project)
        self.project_root = context.project_root
        self.runs_dir = context.runs_dir
        self.recorder = recorder

    def _log_context(self) -> dict[str, object]:
        if self.recorder is None:
            return {}
        return {
            "run_id": self.recorder.store.run_id,
            "task_id": self.recorder.task_id,
            "attempt_id": self.recorder.attempt_id,
        }

    def _log(self, level: int, event_type: str, message: str, **context: object) -> None:
        log_event(LOGGER, level, event_type, message, **self._log_context(), **context)

    def relative_path(self, path: PathLike) -> RelativeCodingPath:
        candidate = Path(path).expanduser()
        if not candidate.is_absolute():
            candidate = self.project_root / candidate
        resolved = candidate.resolve(strict=False)
        try:
            relative = resolved.relative_to(self.project_root)
        except ValueError as exc:
            raise CodingSandboxError(
                f"path {resolved} is not inside project_root {self.project_root}"
            ) from exc
        as_posix = relative.as_posix()
        return "." if not as_posix else as_posix

    def resolve_file(
        self,
        path: PathLike,
        *,
        must_exist: bool = True,
        allow_reserved: bool = False,
        for_write: bool = False,
    ) -> Path:
        resolved = self._resolve_path(path, allow_reserved=allow_reserved)
        if must_exist and not resolved.exists():
            raise FileNotFoundError(f"file does not exist: {resolved}")
        if must_exist and not resolved.is_file():
            raise IsADirectoryError(f"expected a file path: {resolved}")
        if not must_exist and resolved.exists() and not resolved.is_file():
            raise IsADirectoryError(f"expected a file path: {resolved}")
        if for_write and self._is_reserved_path(resolved):
            raise CodingPermissionError(f"writes into reserved framework paths are not allowed: {resolved}")
        return resolved

    def resolve_directory(
        self,
        path: PathLike | None = None,
        *,
        allow_reserved: bool = False,
    ) -> Path:
        target = self.project_root if path is None else self._resolve_path(path, allow_reserved=allow_reserved)
        if not target.exists() or not target.is_dir():
            raise NotADirectoryError(f"expected an existing directory: {target}")
        return target

    def _resolve_path(self, path: PathLike, *, allow_reserved: bool = False) -> Path:
        candidate = Path(path).expanduser()
        if not candidate.is_absolute():
            candidate = self.project_root / candidate
        resolved = candidate.resolve(strict=False)
        try:
            resolved.relative_to(self.project_root)
        except ValueError as exc:
            raise CodingSandboxError(
                f"path {resolved} escapes project_root {self.project_root}"
            ) from exc
        if not allow_reserved and self._is_reserved_path(resolved):
            raise CodingPermissionError(f"reserved framework paths are not available to workers: {resolved}")
        return resolved

    def _is_reserved_path(self, path: Path) -> bool:
        try:
            relative = path.relative_to(self.project_root)
        except ValueError:
            return False
        parts = relative.parts
        return bool(parts) and parts[0] in self.reserved_root_dir_names

    def _record_action(
        self,
        kind: CodingActionKind,
        *,
        path: PathLike | None = None,
        argv: list[str] | None = None,
        details: dict[str, object] | None = None,
    ) -> None:
        if self.recorder is None:
            return
        relative_path = None if path is None else self.relative_path(path)
        self.recorder.record(kind, path=relative_path, argv=argv, details=details)

    def _read_text_file(self, path: Path) -> str:
        try:
            return path.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            raise CodingError(f"file is not valid UTF-8 text: {path}") from exc

    @staticmethod
    def _write_text_atomic(path: Path, content: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with NamedTemporaryFile(
            "w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f"{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            handle.write(content)
            temp_path = Path(handle.name)
        temp_path.replace(path)


class ProjectFileService(ProjectSandbox):
    def read_file(self, path: PathLike) -> FileReadResult:
        resolved = self.resolve_file(path)
        content = self._read_text_file(resolved)
        self._record_action(
            CodingActionKind.READ_FILE,
            path=resolved,
            details={"bytes_read": len(content.encode("utf-8"))},
        )
        self._log(
            logging.DEBUG,
            "read_file",
            "read file",
            tool_name="read_file",
            summary=self.relative_path(resolved),
        )
        return FileReadResult(path=self.relative_path(resolved), content=content)

    def read_file_slice(self, path: PathLike, start_line: int, end_line: int) -> FileReadResult:
        if start_line < 1 or end_line < start_line:
            raise ValueError("start_line must be >= 1 and end_line must be >= start_line")
        resolved = self.resolve_file(path)
        lines = self._read_text_file(resolved).splitlines(keepends=True)
        if lines and start_line > len(lines):
            raise ValueError(f"start_line {start_line} is beyond the end of file {resolved}")
        slice_lines = lines[start_line - 1 : end_line]
        actual_end = start_line + len(slice_lines) - 1 if slice_lines else end_line
        content = "".join(slice_lines)
        self._record_action(
            CodingActionKind.READ_FILE_SLICE,
            path=resolved,
            details={
                "start_line": start_line,
                "end_line": actual_end,
                "bytes_read": len(content.encode("utf-8")),
            },
        )
        self._log(
            logging.DEBUG,
            "read_file_slice",
            "read file slice",
            tool_name="read_file_slice",
            summary=f"{self.relative_path(resolved)}:{start_line}-{actual_end}",
        )
        return FileReadResult(
            path=self.relative_path(resolved),
            content=content,
            start_line=start_line,
            end_line=actual_end,
        )

    def write_file(self, path: PathLike, content: str, *, overwrite: bool = False) -> FileWriteResult:
        resolved = self.resolve_file(path, must_exist=False, for_write=True)
        existed = resolved.exists()
        if existed and not overwrite:
            raise FileExistsError(f"file already exists: {resolved}")
        self._write_text_atomic(resolved, content)
        result = FileWriteResult(
            path=self.relative_path(resolved),
            created=not existed,
            overwritten=existed,
            bytes_written=len(content.encode("utf-8")),
        )
        self._record_action(
            CodingActionKind.WRITE_FILE,
            path=resolved,
            details=result.model_dump(mode="json"),
        )
        self._log(
            logging.DEBUG,
            "write_file",
            "wrote file",
            tool_name="write_file",
            summary=result.path,
        )
        return result

    def replace_in_file(self, path: PathLike, old_text: str, new_text: str) -> FileEditResult:
        if not old_text:
            raise ValueError("old_text must not be empty")
        resolved = self.resolve_file(path, for_write=True)
        current_text = self._read_text_file(resolved)
        replacement_count = current_text.count(old_text)
        if replacement_count == 0:
            raise EditConflictError(f"old_text was not found in file: {resolved}")
        if replacement_count != 1:
            raise EditConflictError(
                f"old_text must match exactly once in file {resolved}; matched {replacement_count} times"
            )
        updated_text = current_text.replace(old_text, new_text, 1)
        self._write_text_atomic(resolved, updated_text)
        result = FileEditResult(
            path=self.relative_path(resolved),
            changed=updated_text != current_text,
            replacement_count=1,
            bytes_written=len(updated_text.encode("utf-8")),
        )
        self._record_action(
            CodingActionKind.REPLACE_IN_FILE,
            path=resolved,
            details=result.model_dump(mode="json"),
        )
        self._log(
            logging.DEBUG,
            "replace_in_file",
            "replaced text in file",
            tool_name="replace_in_file",
            summary=result.path,
        )
        return result

    def append_to_file(self, path: PathLike, content: str) -> FileEditResult:
        resolved = self.resolve_file(path, must_exist=False, for_write=True)
        resolved.parent.mkdir(parents=True, exist_ok=True)
        with resolved.open("a", encoding="utf-8") as handle:
            handle.write(content)
        result = FileEditResult(
            path=self.relative_path(resolved),
            changed=bool(content),
            replacement_count=0,
            bytes_written=len(content.encode("utf-8")),
        )
        self._record_action(
            CodingActionKind.APPEND_TO_FILE,
            path=resolved,
            details=result.model_dump(mode="json"),
        )
        self._log(
            logging.DEBUG,
            "append_to_file",
            "appended to file",
            tool_name="append_to_file",
            summary=result.path,
        )
        return result


def _resolve_context(project: FrameworkConfig | FrameworkPaths | PathLike) -> _SandboxContext:
    if isinstance(project, FrameworkConfig):
        return _SandboxContext(project_root=project.paths.project_root, runs_dir=project.paths.runs_dir)
    if isinstance(project, FrameworkPaths):
        return _SandboxContext(project_root=project.project_root, runs_dir=project.runs_dir)
    root = Path(project).expanduser().resolve(strict=False)
    if not root.exists() or not root.is_dir():
        raise CodingSandboxError(f"project_root does not exist or is not a directory: {root}")
    return _SandboxContext(project_root=root, runs_dir=(root / ".aftk" / "runs").resolve(strict=False))


__all__ = [
    "CodingError",
    "CodingPermissionError",
    "CodingSandboxError",
    "EditConflictError",
    "PathLike",
    "ProjectFileService",
    "ProjectSandbox",
]
