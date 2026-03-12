from __future__ import annotations

from pathlib import Path
from typing import Any

from ._path_utils import display_path, resolve_to_cwd
from .errors import CodingToolkitExecutionError


def write_text_file(*, cwd: Path, path: str, content: str) -> dict[str, Any]:
    """Write a full UTF-8 text file, creating parent directories as needed."""

    absolute_path = resolve_to_cwd(path, cwd)
    shown_path = display_path(absolute_path, cwd)
    parent = absolute_path.parent

    try:
        created_parent_directories = not parent.exists()
        parent.mkdir(parents=True, exist_ok=True)
        absolute_path.write_text(content, encoding="utf-8")
    except PermissionError as exc:
        raise CodingToolkitExecutionError(
            kind="permission_denied",
            message=f"Permission denied while writing {shown_path}.",
            retryable=False,
            suggested_action="choose_accessible_path",
            details={"path": shown_path},
        ) from exc
    except (FileExistsError, NotADirectoryError) as exc:
        raise CodingToolkitExecutionError(
            kind="not_a_directory",
            message=f"A parent component of {shown_path} is not a directory.",
            retryable=True,
            suggested_action="choose_directory_path",
            details={"path": shown_path},
        ) from exc

    return {
        "path": shown_path,
        "bytes_written": len(content.encode("utf-8")),
        "created_parent_directories": created_parent_directories,
    }
