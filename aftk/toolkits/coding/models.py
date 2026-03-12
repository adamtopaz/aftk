from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class ToolkitModel(BaseModel):
    """Base model for coding-toolkit inputs and outputs."""

    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class CodingToolErrorInfo(ToolkitModel):
    """Structured error information returned to an agent."""

    kind: str = Field(description="Stable machine-readable error kind.")
    message: str = Field(description="Human-readable explanation of the tool failure.")
    retryable: bool = Field(description="Whether retrying or adjusting the request could succeed.")
    suggested_action: str | None = Field(
        default=None,
        description="Short machine-readable suggestion describing what the agent should try next.",
    )
    details: dict[str, Any] | None = Field(
        default=None,
        description="Optional structured debugging details about the failure.",
    )


class CodingToolSuccess(ToolkitModel):
    """Successful tool-call envelope."""

    ok: Literal[True] = True
    tool: str = Field(description="The tool name that produced this result.")
    data: Any = Field(description="Tool-specific success payload.")


class CodingToolFailure(ToolkitModel):
    """Failed tool-call envelope."""

    ok: Literal[False] = False
    tool: str = Field(description="The tool name that failed.")
    error: CodingToolErrorInfo = Field(description="Structured failure information.")


CodingToolResult = CodingToolSuccess | CodingToolFailure


class ReadInput(ToolkitModel):
    """Input for reading a text file."""

    path: str = Field(description="Path to the file to read, relative to the configured working directory unless absolute.")
    offset: int | None = Field(default=None, ge=1, description="1-based line number to start reading from.")
    limit: int | None = Field(default=None, ge=1, description="Maximum number of lines to read.")


class WriteInput(ToolkitModel):
    """Input for writing a full file."""

    path: str = Field(description="Path to the file to write, relative to the configured working directory unless absolute.")
    content: str = Field(description="Complete file contents to write.")


class EditInput(ToolkitModel):
    """Input for an exact text replacement."""

    path: str = Field(description="Path to the file to edit, relative to the configured working directory unless absolute.")
    old_text: str = Field(
        alias="oldText",
        description="Exact text to find and replace, including whitespace.",
    )
    new_text: str = Field(
        alias="newText",
        description="Replacement text to write in place of oldText.",
    )


class BashInput(ToolkitModel):
    """Input for a shell command."""

    command: str = Field(description="Shell command to execute inside the configured working directory.")
    timeout: int | None = Field(default=None, ge=1, description="Optional timeout in seconds.")


class GrepInput(ToolkitModel):
    """Input for content search."""

    pattern: str = Field(description="Search pattern, interpreted as regex unless literal is true.")
    path: str | None = Field(default=None, description="Optional file or directory to search. Defaults to the configured working directory.")
    glob: str | None = Field(default=None, description="Optional glob pattern used to filter which files are searched.")
    ignore_case: bool | None = Field(
        default=None,
        alias="ignoreCase",
        description="Whether to search case-insensitively.",
    )
    literal: bool | None = Field(default=None, description="Whether to treat pattern as a literal string instead of a regex.")
    context: int | None = Field(default=None, ge=0, description="Number of context lines to show before and after each match.")
    limit: int | None = Field(default=None, ge=1, description="Maximum number of matches to return.")


class FindInput(ToolkitModel):
    """Input for glob-based file search."""

    pattern: str = Field(description="Glob pattern to match, such as '*.py' or 'src/**/*.lean'.")
    path: str | None = Field(default=None, description="Optional file or directory to search from. Defaults to the configured working directory.")
    limit: int | None = Field(default=None, ge=1, description="Maximum number of results to return.")


class LsInput(ToolkitModel):
    """Input for directory listing."""

    path: str | None = Field(default=None, description="Optional directory to list. Defaults to the configured working directory.")
    limit: int | None = Field(default=None, ge=1, description="Maximum number of directory entries to return.")
