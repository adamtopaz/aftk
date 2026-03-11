from __future__ import annotations

from datetime import datetime, timezone
from enum import StrEnum
from typing import Annotated, Any

from pydantic import AwareDatetime, Field, model_validator

from aftk.config import FrameworkModel


NonEmptyString = Annotated[str, Field(min_length=1)]
RelativeCodingPath = Annotated[str, Field(min_length=1)]


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class ProjectPath(FrameworkModel):
    path: RelativeCodingPath


class SearchMatch(FrameworkModel):
    path: RelativeCodingPath
    line: int = Field(ge=1)
    column: int | None = Field(default=None, ge=1)
    snippet: str


class FileReadResult(FrameworkModel):
    path: RelativeCodingPath
    content: str
    start_line: int | None = Field(default=None, ge=1)
    end_line: int | None = Field(default=None, ge=1)

    @model_validator(mode="after")
    def validate_line_range(self) -> FileReadResult:
        has_start = self.start_line is not None
        has_end = self.end_line is not None
        if has_start != has_end:
            raise ValueError("start_line and end_line must be provided together")
        if has_start and has_end and self.end_line < self.start_line:
            raise ValueError("end_line must not be earlier than start_line")
        return self


class FileWriteResult(FrameworkModel):
    path: RelativeCodingPath
    created: bool
    overwritten: bool
    bytes_written: int = Field(ge=0)

    @model_validator(mode="after")
    def validate_write_flags(self) -> FileWriteResult:
        if self.created and self.overwritten:
            raise ValueError("created and overwritten cannot both be true")
        return self


class FileEditResult(FrameworkModel):
    path: RelativeCodingPath
    changed: bool
    replacement_count: int = Field(ge=0)
    bytes_written: int = Field(ge=0)


class CommandResult(FrameworkModel):
    argv: list[NonEmptyString] = Field(min_length=1)
    cwd: RelativeCodingPath
    exit_code: int
    stdout: str
    stderr: str
    duration_seconds: float = Field(ge=0)
    timed_out: bool


class CodingActionKind(StrEnum):
    LIST_PROJECT_FILES = "list_project_files"
    SEARCH_PROJECT_TEXT = "search_project_text"
    READ_FILE = "read_file"
    READ_FILE_SLICE = "read_file_slice"
    WRITE_FILE = "write_file"
    REPLACE_IN_FILE = "replace_in_file"
    APPEND_TO_FILE = "append_to_file"
    RUN_COMMAND = "run_command"
    LAKE_BUILD = "lake_build"


class CodingAction(FrameworkModel):
    kind: CodingActionKind
    run_id: NonEmptyString
    task_id: NonEmptyString | None = None
    attempt_id: NonEmptyString | None = None
    timestamp: AwareDatetime = Field(default_factory=utc_now)
    path: RelativeCodingPath | None = None
    argv: list[NonEmptyString] | None = None
    details: dict[str, Any] = Field(default_factory=dict)


__all__ = [
    "CodingAction",
    "CodingActionKind",
    "CommandResult",
    "FileEditResult",
    "FileReadResult",
    "FileWriteResult",
    "NonEmptyString",
    "ProjectPath",
    "RelativeCodingPath",
    "SearchMatch",
    "utc_now",
]
