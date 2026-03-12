from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

from .models import CodingToolErrorInfo, CodingToolFailure


@dataclass(slots=True)
class CodingToolkitExecutionError(Exception):
    """Internal exception used for expected coding-toolkit failures."""

    kind: str
    message: str
    retryable: bool
    suggested_action: str | None = None
    details: dict[str, Any] | None = None

    def __post_init__(self) -> None:
        Exception.__init__(self, self.message)


def failure_from_exception(tool_name: str, exc: Exception) -> CodingToolFailure:
    """Convert an expected failure into a structured tool result."""

    return CodingToolFailure(tool=tool_name, error=error_info_from_exception(exc))


def error_info_from_exception(exc: Exception) -> CodingToolErrorInfo:
    """Map an exception to an agent-facing error payload."""

    if isinstance(exc, CodingToolkitExecutionError):
        return CodingToolErrorInfo(
            kind=exc.kind,
            message=exc.message,
            retryable=exc.retryable,
            suggested_action=exc.suggested_action,
            details=exc.details,
        )

    if isinstance(exc, FileNotFoundError):
        return CodingToolErrorInfo(
            kind="path_not_found",
            message=str(exc),
            retryable=True,
            suggested_action="check_path",
            details={"path": exc.filename} if exc.filename is not None else None,
        )

    if isinstance(exc, NotADirectoryError):
        return CodingToolErrorInfo(
            kind="not_a_directory",
            message=str(exc),
            retryable=True,
            suggested_action="choose_directory_path",
            details={"path": exc.filename} if exc.filename is not None else None,
        )

    if isinstance(exc, PermissionError):
        return CodingToolErrorInfo(
            kind="permission_denied",
            message=str(exc),
            retryable=False,
            suggested_action="choose_accessible_path",
            details={"path": exc.filename} if exc.filename is not None else None,
        )

    if isinstance(exc, UnicodeDecodeError):
        return CodingToolErrorInfo(
            kind="decode_error",
            message="The file could not be decoded as UTF-8 text.",
            retryable=False,
            suggested_action="use_bash_or_choose_text_file",
            details={"encoding": exc.encoding, "start": exc.start, "end": exc.end},
        )

    if isinstance(exc, re.error):
        return CodingToolErrorInfo(
            kind="invalid_pattern",
            message=str(exc),
            retryable=True,
            suggested_action="fix_pattern",
        )

    return CodingToolErrorInfo(
        kind="tool_internal_error",
        message=str(exc) or exc.__class__.__name__,
        retryable=False,
        suggested_action="report_failure",
        details={"exception_type": exc.__class__.__name__},
    )
