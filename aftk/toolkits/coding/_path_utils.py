from __future__ import annotations

from pathlib import Path


def expand_path(file_path: str) -> str:
    """Expand a user-supplied path string."""

    normalized = file_path[1:] if file_path.startswith("@") else file_path
    if normalized == "~":
        return str(Path.home())
    if normalized.startswith("~/"):
        return str(Path.home() / normalized[2:])
    return normalized


def resolve_to_cwd(file_path: str, cwd: Path) -> Path:
    """Resolve a path against the configured working directory."""

    expanded = Path(expand_path(file_path)).expanduser()
    if expanded.is_absolute():
        return expanded.resolve(strict=False)
    return (cwd / expanded).resolve(strict=False)


def display_path(path: Path, cwd: Path) -> str:
    """Format a path for agent-facing payloads."""

    try:
        relative = path.relative_to(cwd)
    except ValueError:
        return path.as_posix()

    text = relative.as_posix()
    return text or "."


def display_relative_path(path: Path, root: Path) -> str:
    """Format a path relative to a search root."""

    try:
        relative = path.relative_to(root)
    except ValueError:
        return path.as_posix()

    text = relative.as_posix()
    return text or "."
