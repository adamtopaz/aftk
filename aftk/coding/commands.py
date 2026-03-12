from __future__ import annotations

import logging
import subprocess
import time
from collections.abc import Sequence

from aftk.coding.filesystem import PathLike, ProjectSandbox
from aftk.coding.models import CodingActionKind, CommandResult


class ProjectCommandService(ProjectSandbox):
    def run_command(
        self,
        argv: Sequence[str],
        *,
        cwd: PathLike | None = None,
        timeout_seconds: float | None = None,
    ) -> CommandResult:
        return self._run_command(
            argv,
            cwd=cwd,
            timeout_seconds=timeout_seconds,
            action_kind=CodingActionKind.RUN_COMMAND,
        )

    def lake_build(self, *, target: str | None = None, timeout_seconds: float | None = None) -> CommandResult:
        if target is not None and not target:
            raise ValueError("target must not be empty when provided")
        argv = ["lake", "build"]
        if target is not None:
            argv.append(target)
        return self._run_command(
            argv,
            timeout_seconds=timeout_seconds,
            action_kind=CodingActionKind.LAKE_BUILD,
        )

    def _run_command(
        self,
        argv: Sequence[str],
        *,
        cwd: PathLike | None = None,
        timeout_seconds: float | None = None,
        action_kind: CodingActionKind,
    ) -> CommandResult:
        argv_list = list(argv)
        if not argv_list:
            raise ValueError("argv must not be empty")
        if timeout_seconds is not None and timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive when provided")

        working_directory = self.resolve_directory(cwd, allow_reserved=False)
        self._log(
            logging.INFO,
            "command_start",
            "starting command",
            command=argv_list,
            cwd=self.relative_path(working_directory),
        )
        started = time.perf_counter()
        try:
            completed = subprocess.run(
                argv_list,
                cwd=working_directory,
                capture_output=True,
                text=True,
                timeout=timeout_seconds,
                check=False,
            )
            result = CommandResult(
                argv=argv_list,
                cwd=self.relative_path(working_directory),
                exit_code=completed.returncode,
                stdout=completed.stdout,
                stderr=completed.stderr,
                duration_seconds=time.perf_counter() - started,
                timed_out=False,
            )
        except subprocess.TimeoutExpired as exc:
            result = CommandResult(
                argv=argv_list,
                cwd=self.relative_path(working_directory),
                exit_code=-1,
                stdout=_ensure_text(exc.stdout),
                stderr=_ensure_text(exc.stderr),
                duration_seconds=time.perf_counter() - started,
                timed_out=True,
            )

        self._record_action(
            action_kind,
            argv=argv_list,
            details={
                "cwd": result.cwd,
                "exit_code": result.exit_code,
                "timed_out": result.timed_out,
                "duration_seconds": result.duration_seconds,
            },
        )
        self._log(
            logging.WARNING if result.timed_out or result.exit_code != 0 else logging.INFO,
            "command_end",
            "finished command",
            command=result.argv,
            cwd=result.cwd,
            exit_code=result.exit_code,
            timed_out=result.timed_out,
            duration_s=result.duration_seconds,
            stdout_preview=_preview_output(result.stdout),
            stderr_preview=_preview_output(result.stderr),
        )
        return result


def _ensure_text(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def _preview_output(value: str, *, limit: int = 240) -> str | None:
    stripped = value.strip()
    if not stripped:
        return None
    if len(stripped) <= limit:
        return stripped
    return f"{stripped[: limit - 3]}..."


__all__ = ["ProjectCommandService"]
