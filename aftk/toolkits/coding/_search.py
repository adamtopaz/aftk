from __future__ import annotations

import fnmatch
import os
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Any, Iterator, cast

from pathspec.gitignore import GitIgnoreSpec
from pathspec.util import normalize_file

from ._path_utils import display_path, display_relative_path, resolve_to_cwd
from ._truncate import DEFAULT_MAX_BYTES, GREP_MAX_LINE_LENGTH, TruncationInfo, format_size, truncate_head, truncate_line
from .errors import CodingToolkitExecutionError

DEFAULT_GREP_LIMIT = 100
DEFAULT_FIND_LIMIT = 1000
DEFAULT_LS_LIMIT = 500


class GitIgnoreMatcher:
    """Apply root and nested .gitignore files relative to a search root."""

    def __init__(self, root: Path) -> None:
        self._root = root
        self._spec_cache: dict[Path, GitIgnoreSpec | None] = {}

    def is_ignored(self, path: Path, *, is_dir: bool) -> bool:
        try:
            relative = path.relative_to(self._root)
        except ValueError:
            return False

        ignored: bool | None = None
        for directory in self._applicable_directories(relative):
            spec = self._spec_for_directory(directory)
            if spec is None:
                continue
            local_relative = path.relative_to(directory).as_posix()
            if is_dir:
                local_relative += "/"
            patterns = cast(Any, list(enumerate(spec.patterns)))
            decision, _index = spec._match_file(patterns, normalize_file(local_relative))
            if decision is not None:
                ignored = bool(decision)
        return bool(ignored)

    def _applicable_directories(self, relative: Path) -> list[Path]:
        directories = [self._root]
        current = self._root
        for part in relative.parts[:-1]:
            current = current / part
            directories.append(current)
        return directories

    def _spec_for_directory(self, directory: Path) -> GitIgnoreSpec | None:
        if directory in self._spec_cache:
            return self._spec_cache[directory]

        gitignore_path = directory / ".gitignore"
        if not gitignore_path.is_file():
            self._spec_cache[directory] = None
            return None

        try:
            lines = gitignore_path.read_text(encoding="utf-8", errors="ignore").splitlines()
        except OSError:
            self._spec_cache[directory] = None
            return None

        spec = GitIgnoreSpec.from_lines(lines)
        self._spec_cache[directory] = spec
        return spec


def grep_text(
    *,
    cwd: Path,
    path: str | None,
    pattern: str,
    glob: str | None,
    ignore_case: bool | None,
    literal: bool | None,
    context: int | None,
    limit: int | None,
    follow_gitignore: bool,
) -> dict[str, Any]:
    """Search file contents with regex or literal matching."""

    search_path = resolve_to_cwd(path or ".", cwd)
    shown_search_path = display_path(search_path, cwd)
    if not search_path.exists():
        raise CodingToolkitExecutionError(
            kind="path_not_found",
            message=f"Path not found: {shown_search_path}",
            retryable=True,
            suggested_action="check_path",
            details={"path": shown_search_path},
        )

    regex = _compile_pattern(pattern, ignore_case=bool(ignore_case), literal=bool(literal))
    context_value = max(0, context or 0)
    effective_limit = max(1, limit or DEFAULT_GREP_LIMIT)
    matcher = GitIgnoreMatcher(search_path) if follow_gitignore and search_path.is_dir() else None

    output_lines: list[str] = []
    matches_returned = 0
    match_limit_reached = False
    lines_truncated = False

    for file_path, display_name in _iter_search_files(search_path):
        if matcher is not None and matcher.is_ignored(file_path, is_dir=False):
            continue
        if glob is not None and not _matches_glob(display_name, glob):
            continue

        text = _read_text_for_search(file_path)
        if text is None:
            continue
        lines = _normalize_newlines(text).split("\n")

        for line_number, line_text in enumerate(lines, start=1):
            if regex.search(line_text) is None:
                continue
            if matches_returned >= effective_limit:
                match_limit_reached = True
                break
            matches_returned += 1
            block, block_truncated = _format_grep_block(display_name, lines, line_number, context_value)
            output_lines.extend(block)
            lines_truncated = lines_truncated or block_truncated
        if match_limit_reached:
            break

    if matches_returned == 0:
        return {
            "text": "No matches found",
            "matches_returned": 0,
            "match_limit_reached": False,
            "lines_truncated": False,
            "truncation": None,
        }

    truncation = truncate_head("\n".join(output_lines), max_lines=sys.maxsize, max_bytes=DEFAULT_MAX_BYTES)
    text_output = str(truncation["content"])
    notices: list[str] = []
    payload_truncation: TruncationInfo | None = None

    if match_limit_reached:
        notices.append(f"{effective_limit} matches limit reached. Use limit={effective_limit * 2} for more")
    if bool(truncation["truncated"]):
        payload_truncation = truncation
        notices.append(f"{format_size(DEFAULT_MAX_BYTES)} limit reached")
    if lines_truncated:
        notices.append(f"Some lines were truncated to {GREP_MAX_LINE_LENGTH} chars. Use read to inspect full lines")
    if notices:
        text_output += f"\n\n[{'. '.join(notices)}]"

    return {
        "text": text_output,
        "matches_returned": matches_returned,
        "match_limit_reached": match_limit_reached,
        "lines_truncated": lines_truncated,
        "truncation": payload_truncation,
    }


def find_paths(
    *,
    cwd: Path,
    path: str | None,
    pattern: str,
    limit: int | None,
    follow_gitignore: bool,
) -> dict[str, Any]:
    """Find files and directories by glob pattern."""

    search_path = resolve_to_cwd(path or ".", cwd)
    shown_search_path = display_path(search_path, cwd)
    if not search_path.exists():
        raise CodingToolkitExecutionError(
            kind="path_not_found",
            message=f"Path not found: {shown_search_path}",
            retryable=True,
            suggested_action="check_path",
            details={"path": shown_search_path},
        )

    effective_limit = max(1, limit or DEFAULT_FIND_LIMIT)
    matcher = GitIgnoreMatcher(search_path) if follow_gitignore and search_path.is_dir() else None

    results: list[str] = []
    result_limit_reached = False

    for candidate_path, is_dir, display_name in _iter_find_candidates(search_path):
        if matcher is not None and matcher.is_ignored(candidate_path, is_dir=is_dir):
            continue
        if not _matches_glob(display_name, pattern):
            continue
        if len(results) >= effective_limit:
            result_limit_reached = True
            break
        results.append(f"{display_name}/" if is_dir and not display_name.endswith("/") else display_name)

    if not results:
        return {
            "text": "No files found matching pattern",
            "results_returned": 0,
            "result_limit_reached": False,
            "truncation": None,
        }

    results.sort(key=str.casefold)
    truncation = truncate_head("\n".join(results), max_lines=sys.maxsize, max_bytes=DEFAULT_MAX_BYTES)
    text_output = str(truncation["content"])
    payload_truncation: TruncationInfo | None = None
    notices: list[str] = []

    if result_limit_reached:
        notices.append(f"{effective_limit} results limit reached. Use limit={effective_limit * 2} for more")
    if bool(truncation["truncated"]):
        payload_truncation = truncation
        notices.append(f"{format_size(DEFAULT_MAX_BYTES)} limit reached")
    if notices:
        text_output += f"\n\n[{'. '.join(notices)}]"

    return {
        "text": text_output,
        "results_returned": len(results),
        "result_limit_reached": result_limit_reached,
        "truncation": payload_truncation,
    }


def list_directory(*, cwd: Path, path: str | None, limit: int | None) -> dict[str, Any]:
    """List directory contents."""

    directory_path = resolve_to_cwd(path or ".", cwd)
    shown_directory_path = display_path(directory_path, cwd)
    if not directory_path.exists():
        raise CodingToolkitExecutionError(
            kind="path_not_found",
            message=f"Path not found: {shown_directory_path}",
            retryable=True,
            suggested_action="check_path",
            details={"path": shown_directory_path},
        )
    if not directory_path.is_dir():
        raise CodingToolkitExecutionError(
            kind="not_a_directory",
            message=f"Not a directory: {shown_directory_path}",
            retryable=True,
            suggested_action="choose_directory_path",
            details={"path": shown_directory_path},
        )

    try:
        entries = sorted(os.listdir(directory_path), key=str.casefold)
    except PermissionError as exc:
        raise CodingToolkitExecutionError(
            kind="permission_denied",
            message=f"Permission denied while listing {shown_directory_path}.",
            retryable=False,
            suggested_action="choose_accessible_path",
            details={"path": shown_directory_path},
        ) from exc

    effective_limit = max(1, limit or DEFAULT_LS_LIMIT)
    results: list[str] = []
    entry_limit_reached = False

    for index, entry in enumerate(entries):
        if len(results) >= effective_limit:
            if index < len(entries):
                entry_limit_reached = True
            break
        full_path = directory_path / entry
        try:
            suffix = "/" if full_path.is_dir() else ""
        except OSError:
            continue
        results.append(entry + suffix)

    if not results:
        return {
            "text": "(empty directory)",
            "entries_returned": 0,
            "entry_limit_reached": False,
            "truncation": None,
        }

    truncation = truncate_head("\n".join(results), max_lines=sys.maxsize, max_bytes=DEFAULT_MAX_BYTES)
    text_output = str(truncation["content"])
    payload_truncation: TruncationInfo | None = None
    notices: list[str] = []

    if entry_limit_reached:
        notices.append(f"{effective_limit} entries limit reached. Use limit={effective_limit * 2} for more")
    if bool(truncation["truncated"]):
        payload_truncation = truncation
        notices.append(f"{format_size(DEFAULT_MAX_BYTES)} limit reached")
    if notices:
        text_output += f"\n\n[{'. '.join(notices)}]"

    return {
        "text": text_output,
        "entries_returned": len(results),
        "entry_limit_reached": entry_limit_reached,
        "truncation": payload_truncation,
    }


def _compile_pattern(pattern: str, *, ignore_case: bool, literal: bool) -> re.Pattern[str]:
    flags = re.IGNORECASE if ignore_case else 0
    source = re.escape(pattern) if literal else pattern
    try:
        return re.compile(source, flags)
    except re.error as exc:
        raise CodingToolkitExecutionError(
            kind="invalid_pattern",
            message=str(exc),
            retryable=True,
            suggested_action="fix_pattern",
            details={"pattern": pattern},
        ) from exc


def _iter_search_files(search_path: Path) -> Iterator[tuple[Path, str]]:
    if search_path.is_file():
        yield search_path, search_path.name
        return

    for current_root, dirnames, filenames in os.walk(search_path):
        dirnames[:] = sorted([name for name in dirnames if name != ".git"], key=str.casefold)
        for filename in sorted(filenames, key=str.casefold):
            file_path = Path(current_root) / filename
            yield file_path, display_relative_path(file_path, search_path)


def _iter_find_candidates(search_path: Path) -> Iterator[tuple[Path, bool, str]]:
    if search_path.is_file():
        yield search_path, False, search_path.name
        return

    for current_root, dirnames, filenames in os.walk(search_path):
        dirnames[:] = sorted([name for name in dirnames if name != ".git"], key=str.casefold)
        for dirname in dirnames:
            directory_path = Path(current_root) / dirname
            yield directory_path, True, display_relative_path(directory_path, search_path)
        for filename in sorted(filenames, key=str.casefold):
            file_path = Path(current_root) / filename
            yield file_path, False, display_relative_path(file_path, search_path)


def _read_text_for_search(path: Path) -> str | None:
    try:
        data = path.read_bytes()
    except OSError:
        return None

    if _looks_binary(data):
        return None

    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def _looks_binary(data: bytes) -> bool:
    return b"\x00" in data[:8192]


def _normalize_newlines(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


def _format_grep_block(display_name: str, lines: list[str], line_number: int, context: int) -> tuple[list[str], bool]:
    block: list[str] = []
    lines_truncated = False
    start = max(1, line_number - context) if context > 0 else line_number
    end = min(len(lines), line_number + context) if context > 0 else line_number

    for current_line in range(start, end + 1):
        line_text = lines[current_line - 1] if current_line - 1 < len(lines) else ""
        truncated_text, was_truncated = truncate_line(line_text.replace("\r", ""))
        lines_truncated = lines_truncated or was_truncated
        if current_line == line_number:
            block.append(f"{display_name}:{current_line}: {truncated_text}")
        else:
            block.append(f"{display_name}-{current_line}- {truncated_text}")
    return block, lines_truncated


def _matches_glob(relative_path: str, pattern: str) -> bool:
    normalized_path = relative_path.rstrip("/")
    normalized_pattern = pattern.replace("\\", "/").rstrip("/")
    candidate = PurePosixPath(normalized_path)

    patterns = [normalized_pattern]
    if normalized_pattern.startswith("**/"):
        patterns.append(normalized_pattern[3:])

    for candidate_pattern in patterns:
        if candidate.match(candidate_pattern):
            return True
        if "/" not in candidate_pattern and fnmatch.fnmatch(candidate.name, candidate_pattern):
            return True
    return False
