from __future__ import annotations

from typing import Literal, TypedDict

DEFAULT_MAX_LINES = 2000
DEFAULT_MAX_BYTES = 50 * 1024
GREP_MAX_LINE_LENGTH = 500


class TruncationInfo(TypedDict):
    content: str
    truncated: bool
    truncated_by: Literal["lines", "bytes"] | None
    total_lines: int
    total_bytes: int
    output_lines: int
    output_bytes: int
    last_line_partial: bool
    first_line_exceeds_limit: bool
    max_lines: int
    max_bytes: int


def format_size(byte_count: int) -> str:
    """Format a byte count as a readable size."""

    if byte_count < 1024:
        return f"{byte_count}B"
    if byte_count < 1024 * 1024:
        return f"{byte_count / 1024:.1f}KB"
    return f"{byte_count / (1024 * 1024):.1f}MB"


def truncate_head(content: str, *, max_lines: int = DEFAULT_MAX_LINES, max_bytes: int = DEFAULT_MAX_BYTES) -> TruncationInfo:
    """Truncate content from the head without returning partial lines."""

    total_bytes = len(content.encode("utf-8"))
    lines = content.split("\n")
    total_lines = len(lines)

    if total_lines <= max_lines and total_bytes <= max_bytes:
        return {
            "content": content,
            "truncated": False,
            "truncated_by": None,
            "total_lines": total_lines,
            "total_bytes": total_bytes,
            "output_lines": total_lines,
            "output_bytes": total_bytes,
            "last_line_partial": False,
            "first_line_exceeds_limit": False,
            "max_lines": max_lines,
            "max_bytes": max_bytes,
        }

    first_line_bytes = len(lines[0].encode("utf-8"))
    if first_line_bytes > max_bytes:
        return {
            "content": "",
            "truncated": True,
            "truncated_by": "bytes",
            "total_lines": total_lines,
            "total_bytes": total_bytes,
            "output_lines": 0,
            "output_bytes": 0,
            "last_line_partial": False,
            "first_line_exceeds_limit": True,
            "max_lines": max_lines,
            "max_bytes": max_bytes,
        }

    output_lines: list[str] = []
    output_bytes = 0
    truncated_by: str = "lines"

    for index, line in enumerate(lines[:max_lines]):
        line_bytes = len(line.encode("utf-8")) + (1 if index > 0 else 0)
        if output_bytes + line_bytes > max_bytes:
            truncated_by = "bytes"
            break
        output_lines.append(line)
        output_bytes += line_bytes

    if len(output_lines) >= max_lines and output_bytes <= max_bytes:
        truncated_by = "lines"

    output_content = "\n".join(output_lines)
    final_output_bytes = len(output_content.encode("utf-8"))
    return {
        "content": output_content,
        "truncated": True,
        "truncated_by": truncated_by,
        "total_lines": total_lines,
        "total_bytes": total_bytes,
        "output_lines": len(output_lines),
        "output_bytes": final_output_bytes,
        "last_line_partial": False,
        "first_line_exceeds_limit": False,
        "max_lines": max_lines,
        "max_bytes": max_bytes,
    }


def truncate_tail(content: str, *, max_lines: int = DEFAULT_MAX_LINES, max_bytes: int = DEFAULT_MAX_BYTES) -> TruncationInfo:
    """Truncate content from the tail, allowing a partial first line if needed."""

    total_bytes = len(content.encode("utf-8"))
    lines = content.split("\n")
    total_lines = len(lines)

    if total_lines <= max_lines and total_bytes <= max_bytes:
        return {
            "content": content,
            "truncated": False,
            "truncated_by": None,
            "total_lines": total_lines,
            "total_bytes": total_bytes,
            "output_lines": total_lines,
            "output_bytes": total_bytes,
            "last_line_partial": False,
            "first_line_exceeds_limit": False,
            "max_lines": max_lines,
            "max_bytes": max_bytes,
        }

    output_lines: list[str] = []
    output_bytes = 0
    truncated_by: str = "lines"
    last_line_partial = False

    for line in reversed(lines):
        if len(output_lines) >= max_lines:
            break
        line_bytes = len(line.encode("utf-8")) + (1 if output_lines else 0)
        if output_bytes + line_bytes > max_bytes:
            truncated_by = "bytes"
            if not output_lines:
                truncated_line = _truncate_string_to_bytes_from_end(line, max_bytes)
                output_lines.insert(0, truncated_line)
                output_bytes = len(truncated_line.encode("utf-8"))
                last_line_partial = True
            break
        output_lines.insert(0, line)
        output_bytes += line_bytes

    if len(output_lines) >= max_lines and output_bytes <= max_bytes:
        truncated_by = "lines"

    output_content = "\n".join(output_lines)
    final_output_bytes = len(output_content.encode("utf-8"))
    return {
        "content": output_content,
        "truncated": True,
        "truncated_by": truncated_by,
        "total_lines": total_lines,
        "total_bytes": total_bytes,
        "output_lines": len(output_lines),
        "output_bytes": final_output_bytes,
        "last_line_partial": last_line_partial,
        "first_line_exceeds_limit": False,
        "max_lines": max_lines,
        "max_bytes": max_bytes,
    }


def truncate_line(line: str, max_chars: int = GREP_MAX_LINE_LENGTH) -> tuple[str, bool]:
    """Truncate a single line for search results."""

    if len(line) <= max_chars:
        return line, False
    return f"{line[:max_chars]}... [truncated]", True


def _truncate_string_to_bytes_from_end(text: str, max_bytes: int) -> str:
    data = text.encode("utf-8")
    if len(data) <= max_bytes:
        return text

    start = len(data) - max_bytes
    while start < len(data) and (data[start] & 0xC0) == 0x80:
        start += 1
    return data[start:].decode("utf-8", errors="replace")
