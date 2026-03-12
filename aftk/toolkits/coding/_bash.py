from __future__ import annotations

import asyncio
import os
import tempfile
from pathlib import Path
from typing import Any

from ._truncate import DEFAULT_MAX_BYTES, TruncationInfo, format_size, truncate_tail
from .errors import CodingToolkitExecutionError


async def run_bash_command(*, cwd: Path, command: str, timeout: int | None) -> dict[str, Any]:
    """Execute a shell command and return bounded combined output."""

    if not cwd.exists():
        raise CodingToolkitExecutionError(
            kind="path_not_found",
            message=f"Working directory does not exist: {cwd.as_posix()}",
            retryable=False,
            suggested_action="fix_cwd",
            details={"cwd": cwd.as_posix()},
        )
    if not cwd.is_dir():
        raise CodingToolkitExecutionError(
            kind="not_a_directory",
            message=f"Working directory is not a directory: {cwd.as_posix()}",
            retryable=False,
            suggested_action="fix_cwd",
            details={"cwd": cwd.as_posix()},
        )

    shell = _resolve_shell()
    try:
        process = await asyncio.create_subprocess_exec(
            shell,
            "-c",
            command,
            cwd=str(cwd),
            env=os.environ.copy(),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
    except FileNotFoundError as exc:
        raise CodingToolkitExecutionError(
            kind="tool_internal_error",
            message=f"Shell executable not found: {shell}",
            retryable=False,
            suggested_action="report_failure",
            details={"shell": shell},
        ) from exc

    assert process.stdout is not None
    chunks: list[bytes] = []
    reader = asyncio.create_task(_read_stream(process.stdout, chunks))

    try:
        if timeout is None:
            await process.wait()
        else:
            await asyncio.wait_for(process.wait(), timeout=timeout)
    except asyncio.TimeoutError as exc:
        process.kill()
        await process.wait()
        await reader
        output = b"".join(chunks).decode("utf-8", errors="replace")
        rendered_output, truncation, full_output_path = _render_bash_output(output)
        message = rendered_output
        if message:
            message += "\n\n"
        message += f"Command timed out after {timeout} seconds"
        raise CodingToolkitExecutionError(
            kind="timeout",
            message=message,
            retryable=True,
            suggested_action="retry",
            details={
                "command": command,
                "cwd": cwd.as_posix(),
                "timeout": timeout,
                "text": rendered_output,
                "truncation": truncation,
                "full_output_path": full_output_path,
            },
        ) from exc

    await reader
    output = b"".join(chunks).decode("utf-8", errors="replace")
    rendered_output, truncation, full_output_path = _render_bash_output(output)

    if process.returncode not in (0, None):
        message = rendered_output
        if message:
            message += "\n\n"
        message += f"Command exited with code {process.returncode}"
        raise CodingToolkitExecutionError(
            kind="command_failed",
            message=message,
            retryable=False,
            suggested_action="inspect_command_or_output",
            details={
                "command": command,
                "cwd": cwd.as_posix(),
                "exit_code": process.returncode,
                "text": rendered_output,
                "truncation": truncation,
                "full_output_path": full_output_path,
            },
        )

    return {
        "text": rendered_output,
        "exit_code": process.returncode or 0,
        "truncation": truncation,
        "full_output_path": full_output_path,
    }


async def _read_stream(stream: asyncio.StreamReader, chunks: list[bytes]) -> None:
    while True:
        chunk = await stream.read(4096)
        if not chunk:
            return
        chunks.append(chunk)


def _resolve_shell() -> str:
    env_shell = os.environ.get("SHELL")
    for candidate in [env_shell, "/bin/bash", "/bin/sh"]:
        if candidate and Path(candidate).exists():
            return candidate
    return "/bin/sh"


def _render_bash_output(output: str) -> tuple[str, TruncationInfo | None, str | None]:
    truncation = truncate_tail(output)
    rendered = str(truncation["content"]) or "(no output)"
    full_output_path: str | None = None
    payload_truncation: TruncationInfo | None = None

    if bool(truncation["truncated"]):
        payload_truncation = truncation
        full_output_path = _write_temp_output(output)
        start_line = int(truncation["total_lines"]) - int(truncation["output_lines"]) + 1
        end_line = int(truncation["total_lines"])
        if bool(truncation["last_line_partial"]):
            rendered += (
                f"\n\n[Showing last {format_size(int(truncation['output_bytes']))} of line {end_line}. "
                f"Full output: {full_output_path}]"
            )
        elif truncation["truncated_by"] == "lines":
            rendered += f"\n\n[Showing lines {start_line}-{end_line} of {truncation['total_lines']}. Full output: {full_output_path}]"
        else:
            rendered += (
                f"\n\n[Showing lines {start_line}-{end_line} of {truncation['total_lines']} "
                f"({format_size(DEFAULT_MAX_BYTES)} limit). Full output: {full_output_path}]"
            )

    return rendered, payload_truncation, full_output_path


def _write_temp_output(output: str) -> str:
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".log", prefix="aftk-bash-", delete=False) as handle:
        handle.write(output)
        return handle.name
