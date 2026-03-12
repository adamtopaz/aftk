from __future__ import annotations

import codecs
import difflib
from pathlib import Path
from typing import Any

from ._path_utils import display_path, resolve_to_cwd
from .errors import CodingToolkitExecutionError


def edit_text_file(*, cwd: Path, path: str, old_text: str, new_text: str) -> dict[str, Any]:
    """Replace exact text in a UTF-8 file while preserving BOM and line endings."""

    absolute_path = resolve_to_cwd(path, cwd)
    shown_path = display_path(absolute_path, cwd)

    if old_text == "":
        raise CodingToolkitExecutionError(
            kind="invalid_edit",
            message="oldText must not be empty.",
            retryable=True,
            suggested_action="provide_old_text",
        )

    if absolute_path.exists() and absolute_path.is_dir():
        raise CodingToolkitExecutionError(
            kind="not_a_file",
            message=f"Path is a directory, not a file: {shown_path}",
            retryable=True,
            suggested_action="choose_file_path",
            details={"path": shown_path},
        )

    try:
        raw = absolute_path.read_bytes()
    except FileNotFoundError as exc:
        raise CodingToolkitExecutionError(
            kind="file_not_found",
            message=f"File not found: {shown_path}",
            retryable=True,
            suggested_action="check_path",
            details={"path": shown_path},
        ) from exc
    except PermissionError as exc:
        raise CodingToolkitExecutionError(
            kind="permission_denied",
            message=f"Permission denied while editing {shown_path}.",
            retryable=False,
            suggested_action="choose_accessible_path",
            details={"path": shown_path},
        ) from exc

    bom = raw.startswith(codecs.BOM_UTF8)
    raw_text_bytes = raw[len(codecs.BOM_UTF8) :] if bom else raw

    try:
        content = raw_text_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise CodingToolkitExecutionError(
            kind="decode_error",
            message=f"File is not valid UTF-8 text: {shown_path}",
            retryable=False,
            suggested_action="use_bash_or_choose_text_file",
            details={"path": shown_path},
        ) from exc

    original_ending = detect_line_ending(content)
    normalized_content = normalize_to_lf(content)
    normalized_old_text = normalize_to_lf(old_text)
    normalized_new_text = normalize_to_lf(new_text)

    occurrences = normalized_content.count(normalized_old_text)
    if occurrences == 0:
        raise CodingToolkitExecutionError(
            kind="text_not_found",
            message=f"Could not find the exact text in {shown_path}.",
            retryable=True,
            suggested_action="provide_more_exact_context",
            details={"path": shown_path},
        )
    if occurrences > 1:
        raise CodingToolkitExecutionError(
            kind="ambiguous_edit",
            message=f"Found {occurrences} occurrences of the requested text in {shown_path}.",
            retryable=True,
            suggested_action="make_old_text_unique",
            details={"path": shown_path, "occurrences": occurrences},
        )

    updated_content = normalized_content.replace(normalized_old_text, normalized_new_text, 1)
    if updated_content == normalized_content:
        raise CodingToolkitExecutionError(
            kind="no_change",
            message=f"The requested replacement would not change {shown_path}.",
            retryable=True,
            suggested_action="change_new_text",
            details={"path": shown_path},
        )

    final_text = restore_line_endings(updated_content, original_ending)
    final_bytes = (codecs.BOM_UTF8 if bom else b"") + final_text.encode("utf-8")

    try:
        absolute_path.write_bytes(final_bytes)
    except PermissionError as exc:
        raise CodingToolkitExecutionError(
            kind="permission_denied",
            message=f"Permission denied while editing {shown_path}.",
            retryable=False,
            suggested_action="choose_accessible_path",
            details={"path": shown_path},
        ) from exc

    diff = generate_unified_diff(normalized_content, updated_content)
    return {
        "path": shown_path,
        "diff": diff,
        "first_changed_line": first_changed_line(normalized_content, updated_content),
    }


def detect_line_ending(content: str) -> str:
    """Detect the dominant line ending used in a file."""

    crlf_index = content.find("\r\n")
    lf_index = content.find("\n")
    if lf_index == -1:
        return "\n"
    if crlf_index == -1:
        return "\n"
    return "\r\n" if crlf_index < lf_index else "\n"


def normalize_to_lf(text: str) -> str:
    """Normalize line endings to LF."""

    return text.replace("\r\n", "\n").replace("\r", "\n")


def restore_line_endings(text: str, line_ending: str) -> str:
    """Restore normalized content to the original line ending style."""

    if line_ending == "\r\n":
        return text.replace("\n", "\r\n")
    return text


def generate_unified_diff(before: str, after: str) -> str:
    """Generate a unified diff string."""

    diff_lines = difflib.unified_diff(
        before.splitlines(),
        after.splitlines(),
        fromfile="before",
        tofile="after",
        lineterm="",
        n=4,
    )
    return "\n".join(diff_lines)


def first_changed_line(before: str, after: str) -> int | None:
    """Return the first changed line number in the new content."""

    matcher = difflib.SequenceMatcher(a=before.splitlines(), b=after.splitlines())
    for tag, _i1, _i2, j1, _j2 in matcher.get_opcodes():
        if tag != "equal":
            return j1 + 1
    return None
