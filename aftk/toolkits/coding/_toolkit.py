from __future__ import annotations

from collections.abc import Callable
from pathlib import Path
from typing import Any

from pydantic import BaseModel
from pydantic_ai.toolsets import CombinedToolset, FunctionToolset, WrapperToolset

from ._bash import run_bash_command
from ._edit import edit_text_file
from ._read import read_text_file
from ._search import find_paths, grep_text, list_directory
from ._write import write_text_file
from .errors import failure_from_exception
from .models import (
    BashInput,
    CodingToolFailure,
    CodingToolSuccess,
    EditInput,
    FindInput,
    GrepInput,
    LsInput,
    ReadInput,
    WriteInput,
)


class CodingToolkit(WrapperToolset[Any]):
    """Pydantic AI toolset exposing local coding tools."""

    def __init__(
        self,
        *,
        cwd: str | Path | None = None,
        read_only: bool = False,
        include_search: bool = True,
        follow_gitignore: bool = True,
        id: str | None = None,
    ) -> None:
        resolved_cwd = Path.cwd() if cwd is None else Path(cwd).expanduser().resolve(strict=False)
        if not resolved_cwd.exists():
            raise ValueError(f"Working directory does not exist: {resolved_cwd}")
        if not resolved_cwd.is_dir():
            raise ValueError(f"Working directory is not a directory: {resolved_cwd}")

        self._cwd = resolved_cwd
        self._read_only = read_only
        self._include_search = include_search
        self._follow_gitignore = follow_gitignore
        self._id = id
        self.wrapped = self._build_wrapped_toolset()

    @property
    def id(self) -> str | None:
        return self._id

    async def call_tool(self, name: str, tool_args: dict[str, Any], ctx: Any, tool: Any) -> Any:
        try:
            result = await self.wrapped.call_tool(name, tool_args, ctx, tool)
        except Exception as exc:
            return failure_from_exception(name, exc)

        if isinstance(result, (CodingToolSuccess, CodingToolFailure)):
            return result
        return CodingToolSuccess(tool=name, data=self._normalize_result(result))

    def apply(self, visitor: Callable[[Any], None]) -> None:
        self.wrapped.apply(visitor)

    def visit_and_replace(self, visitor: Callable[[Any], Any]) -> Any:
        clone = self.__class__(
            cwd=self._cwd,
            read_only=self._read_only,
            include_search=self._include_search,
            follow_gitignore=self._follow_gitignore,
            id=self._id,
        )
        clone.wrapped = self.wrapped.visit_and_replace(visitor)
        return clone

    def _build_wrapped_toolset(self) -> CombinedToolset[Any]:
        toolsets: list[FunctionToolset[Any]] = [self._build_read_toolset()]
        if not self._read_only:
            toolsets.append(self._build_write_toolset())
            toolsets.append(self._build_shell_toolset())
        if self._include_search:
            toolsets.append(self._build_search_toolset())
        return CombinedToolset(toolsets=toolsets)

    def _build_read_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="filesystem", suffix="read")
        self._register(toolset, self._read, name="read", mutates=False)
        return toolset

    def _build_write_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="filesystem", suffix="write")
        self._register(toolset, self._write, name="write", mutates=True)
        self._register(toolset, self._edit, name="edit", mutates=True)
        return toolset

    def _build_shell_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="shell", suffix="shell")
        self._register(toolset, self._bash, name="bash", mutates=True)
        return toolset

    def _build_search_toolset(self) -> FunctionToolset[Any]:
        toolset = self._new_function_toolset(layer="filesystem", suffix="search")
        self._register(toolset, self._grep, name="grep", mutates=False)
        self._register(toolset, self._find, name="find", mutates=False)
        self._register(toolset, self._ls, name="ls", mutates=False)
        return toolset

    def _new_function_toolset(self, *, layer: str, suffix: str) -> FunctionToolset[Any]:
        return FunctionToolset(
            docstring_format="google",
            require_parameter_descriptions=True,
            sequential=True,
            metadata={"source": "coding", "layer": layer},
            id=self._toolset_id(suffix),
        )

    def _register(self, toolset: FunctionToolset[Any], func: Callable[..., Any], *, name: str, mutates: bool) -> None:
        toolset.add_function(
            func,
            name=name,
            metadata={"mutates": mutates, "read_only": not mutates},
        )

    def _toolset_id(self, suffix: str) -> str | None:
        if self._id is None:
            return None
        return f"{self._id}:{suffix}"

    @staticmethod
    def _normalize_result(result: Any) -> Any:
        if isinstance(result, BaseModel):
            return result.model_dump(mode="python", by_alias=True)
        return result

    async def _read(self, params: ReadInput) -> dict[str, Any]:
        """Read a UTF-8 text file.

        Args:
            params: Input parameters describing the file path and optional line window.
        """

        return read_text_file(cwd=self._cwd, path=params.path, offset=params.offset, limit=params.limit)

    async def _write(self, params: WriteInput) -> dict[str, Any]:
        """Write full contents to a file.

        Args:
            params: Input parameters describing the target path and file contents.
        """

        return write_text_file(cwd=self._cwd, path=params.path, content=params.content)

    async def _edit(self, params: EditInput) -> dict[str, Any]:
        """Edit a file by replacing exact text.

        Args:
            params: Input parameters describing the target file and exact replacement text.
        """

        return edit_text_file(cwd=self._cwd, path=params.path, old_text=params.old_text, new_text=params.new_text)

    async def _bash(self, params: BashInput) -> dict[str, Any]:
        """Execute a shell command inside the configured working directory.

        Args:
            params: Input parameters describing the command and optional timeout.
        """

        return await run_bash_command(cwd=self._cwd, command=params.command, timeout=params.timeout)

    async def _grep(self, params: GrepInput) -> dict[str, Any]:
        """Search file contents for literal or regex matches.

        Args:
            params: Input parameters describing the search pattern, path, and output limits.
        """

        return grep_text(
            cwd=self._cwd,
            path=params.path,
            pattern=params.pattern,
            glob=params.glob,
            ignore_case=params.ignore_case,
            literal=params.literal,
            context=params.context,
            limit=params.limit,
            follow_gitignore=self._follow_gitignore,
        )

    async def _find(self, params: FindInput) -> dict[str, Any]:
        """Find files and directories by glob pattern.

        Args:
            params: Input parameters describing the search root, glob pattern, and result limit.
        """

        return find_paths(
            cwd=self._cwd,
            path=params.path,
            pattern=params.pattern,
            limit=params.limit,
            follow_gitignore=self._follow_gitignore,
        )

    async def _ls(self, params: LsInput) -> dict[str, Any]:
        """List directory contents.

        Args:
            params: Input parameters describing the directory and optional result limit.
        """

        return list_directory(cwd=self._cwd, path=params.path, limit=params.limit)
