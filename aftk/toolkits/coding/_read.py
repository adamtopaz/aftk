from __future__ import annotations

from pathlib import Path
from typing import Any

from ._path_utils import display_path, resolve_to_cwd
from ._truncate import DEFAULT_MAX_BYTES, TruncationInfo, format_size, truncate_head
from .errors import CodingToolkitExecutionError


def read_text_file(*, cwd: Path, path: str, offset: int | None, limit: int | None) -> dict[str, Any]:
    """Read and truncate a UTF-8 text file."""

    absolute_path = resolve_to_cwd(path, cwd)
    shown_path = display_path(absolute_path, cwd)

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
            message=f"Permission denied while reading {shown_path}.",
            retryable=False,
            suggested_action="choose_accessible_path",
            details={"path": shown_path},
        ) from exc

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise CodingToolkitExecutionError(
            kind="decode_error",
            message=f"File is not valid UTF-8 text: {shown_path}",
            retryable=False,
            suggested_action="use_bash_or_choose_text_file",
            details={"path": shown_path},
        ) from exc

    all_lines = text.split("\n")
    total_lines = len(all_lines)
    start_index = max(0, (offset or 1) - 1)
    start_line = start_index + 1

    if start_index >= total_lines:
        raise CodingToolkitExecutionError(
            kind="invalid_offset",
            message=f"Offset {offset} is beyond the end of {shown_path} ({total_lines} lines).",
            retryable=True,
            suggested_action="choose_smaller_offset",
            details={"path": shown_path, "offset": offset, "total_lines": total_lines},
        )

    if limit is not None:
        end_index = min(start_index + limit, total_lines)
        selected_content = "\n".join(all_lines[start_index:end_index])
        user_limited_lines = end_index - start_index
    else:
        selected_content = "\n".join(all_lines[start_index:])
        user_limited_lines = None

    truncation = truncate_head(selected_content)
    output_lines = int(truncation["output_lines"])
    end_line = start_line + output_lines - 1
    result_text = str(truncation["content"])
    result_truncation: TruncationInfo | None = None

    if bool(truncation["first_line_exceeds_limit"]):
        first_line_size = format_size(len(all_lines[start_index].encode("utf-8")))
        result_text = (
            f"[Line {start_line} is {first_line_size}, exceeds {format_size(DEFAULT_MAX_BYTES)} limit. "
            "Use bash to inspect this line.]"
        )
        result_truncation = truncation
    elif bool(truncation["truncated"]):
        next_offset = end_line + 1
        if truncation["truncated_by"] == "lines":
            result_text += f"\n\n[Showing lines {start_line}-{end_line} of {total_lines}. Use offset={next_offset} to continue.]"
        else:
            result_text += (
                f"\n\n[Showing lines {start_line}-{end_line} of {total_lines} "
                f"({format_size(DEFAULT_MAX_BYTES)} limit). Use offset={next_offset} to continue.]"
            )
        result_truncation = truncation
    elif user_limited_lines is not None and start_index + user_limited_lines < total_lines:
        remaining = total_lines - (start_index + user_limited_lines)
        next_offset = start_index + user_limited_lines + 1
        result_text += f"\n\n[{remaining} more lines in file. Use offset={next_offset} to continue.]"

    return {
        "path": shown_path,
        "text": result_text,
        "start_line": start_line,
        "end_line": end_line,
        "total_lines": total_lines,
        "truncation": result_truncation,
    }
