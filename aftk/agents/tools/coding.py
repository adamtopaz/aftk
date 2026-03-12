from __future__ import annotations

from collections.abc import Callable
from typing import Any

from aftk.agents.tools.retries import wrap_tool_errors
from aftk.coding.commands import ProjectCommandService
from aftk.coding.filesystem import PathLike, ProjectFileService
from aftk.coding.logs import CodingActionRecorder
from aftk.coding.models import CommandResult, FileEditResult, FileReadResult, FileWriteResult, ProjectPath, SearchMatch
from aftk.coding.search import ProjectSearchService
from aftk.config import FrameworkConfig, FrameworkPaths

try:
    from pydantic_ai import FunctionToolset
except ImportError:  # pragma: no cover - exercised through fallback behavior in tests
    FunctionToolset = None


DEFAULT_CODING_TOOL_RETRIES = 2


class WorkerCodingTools:
    def __init__(
        self,
        project: FrameworkConfig | FrameworkPaths | PathLike,
        *,
        recorder: CodingActionRecorder | None = None,
    ) -> None:
        self.search = ProjectSearchService(project, recorder=recorder)
        self.files = ProjectFileService(project, recorder=recorder)
        self.commands = ProjectCommandService(project, recorder=recorder)

    def list_project_files(
        self,
        include_globs: list[str] | None = None,
        exclude_globs: list[str] | None = None,
        limit: int = 200,
    ) -> list[ProjectPath]:
        """List project files visible to a worker, excluding generated directories by default."""
        return self.search.list_project_files(
            include_globs=include_globs,
            exclude_globs=exclude_globs,
            limit=limit,
        )

    def search_project_text(
        self,
        query: str,
        include_globs: list[str] | None = None,
        exclude_globs: list[str] | None = None,
        limit: int = 100,
    ) -> list[SearchMatch]:
        """Search UTF-8 project files for a text query and return bounded line-level matches."""
        return self.search.search_project_text(
            query,
            include_globs=include_globs,
            exclude_globs=exclude_globs,
            limit=limit,
        )

    def read_file(self, path: str) -> FileReadResult:
        """Read a UTF-8 text file inside the worker sandbox."""
        return self.files.read_file(path)

    def read_file_slice(self, path: str, start_line: int, end_line: int) -> FileReadResult:
        """Read a 1-indexed inclusive line slice from a UTF-8 text file in the worker sandbox."""
        return self.files.read_file_slice(path, start_line, end_line)

    def write_file(self, path: str, content: str, overwrite: bool = False) -> FileWriteResult:
        """Write a UTF-8 text file inside the worker sandbox, optionally overwriting an existing file."""
        return self.files.write_file(path, content, overwrite=overwrite)

    def replace_in_file(self, path: str, old_text: str, new_text: str) -> FileEditResult:
        """Replace one exact text match in a UTF-8 project file inside the worker sandbox."""
        return self.files.replace_in_file(path, old_text, new_text)

    def append_to_file(self, path: str, content: str) -> FileEditResult:
        """Append UTF-8 text to a file inside the worker sandbox, creating the file if needed."""
        return self.files.append_to_file(path, content)

    def run_command(
        self,
        argv: list[str],
        cwd: str | None = None,
        timeout_seconds: float | None = None,
    ) -> CommandResult:
        """Run a command within the project root or one of its non-reserved subdirectories."""
        return self.commands.run_command(argv, cwd=cwd, timeout_seconds=timeout_seconds)

    def lake_build(self, target: str | None = None, timeout_seconds: float | None = None) -> CommandResult:
        """Run `lake build` in the project root, optionally for a specific target."""
        return self.commands.lake_build(target=target, timeout_seconds=timeout_seconds)

    def tool_functions(self) -> tuple[Callable[..., object], ...]:
        return (
            wrap_tool_errors(self.list_project_files),
            wrap_tool_errors(self.search_project_text),
            wrap_tool_errors(self.read_file),
            wrap_tool_errors(self.read_file_slice),
            wrap_tool_errors(self.write_file),
            wrap_tool_errors(self.replace_in_file),
            wrap_tool_errors(self.append_to_file),
            wrap_tool_errors(self.run_command),
            wrap_tool_errors(self.lake_build),
        )


def build_worker_coding_toolset(
    project: FrameworkConfig | FrameworkPaths | PathLike,
    *,
    recorder: CodingActionRecorder | None = None,
) -> Any:
    tools = WorkerCodingTools(project, recorder=recorder)
    if FunctionToolset is None:
        raise RuntimeError("pydantic-ai is not installed; install `pydantic-ai` to build worker coding toolsets")
    return FunctionToolset(
        tools=list(tools.tool_functions()),
        max_retries=DEFAULT_CODING_TOOL_RETRIES,
        sequential=True,
    )


__all__ = ["DEFAULT_CODING_TOOL_RETRIES", "WorkerCodingTools", "build_worker_coding_toolset"]
