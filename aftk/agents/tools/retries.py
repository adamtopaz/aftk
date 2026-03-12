from __future__ import annotations

from collections.abc import Awaitable, Callable
from functools import wraps
from typing import ParamSpec, TypeVar

from pydantic_ai import ModelRetry

from aftk.coding.filesystem import CodingError, CodingPermissionError, CodingSandboxError, EditConflictError
from aftk_client.errors import (
    DomainConflictError,
    DomainNotFoundError,
    DomainOperationError,
    DomainRequestError,
    DomainValidationError,
    FileChangedError,
    FileNotOpenError,
    InvalidParamsError,
    JsonRpcRequestError,
    RequestTimeoutError,
    StaleNodeError,
    TacticFailedError,
    WorkerUnavailableError,
)


P = ParamSpec("P")
T = TypeVar("T")


def wrap_tool_errors(
    func: Callable[P, T],
    *,
    tool_name: str | None = None,
) -> Callable[P, T]:
    resolved_tool_name = tool_name or getattr(func, "__name__", "tool")

    @wraps(func)
    def wrapped(*args: P.args, **kwargs: P.kwargs) -> T:
        try:
            return func(*args, **kwargs)
        except ModelRetry:
            raise
        except Exception as exc:
            _raise_model_retry(resolved_tool_name, exc)

    return wrapped


def wrap_async_tool_errors(
    func: Callable[P, Awaitable[T]],
    *,
    tool_name: str | None = None,
) -> Callable[P, Awaitable[T]]:
    resolved_tool_name = tool_name or getattr(func, "__name__", "tool")

    @wraps(func)
    async def wrapped(*args: P.args, **kwargs: P.kwargs) -> T:
        try:
            return await func(*args, **kwargs)
        except ModelRetry:
            raise
        except Exception as exc:
            _raise_model_retry(resolved_tool_name, exc)

    return wrapped


def _raise_model_retry(tool_name: str, exc: Exception) -> None:
    retry_message = _build_retry_message(tool_name, exc)
    if retry_message is None:
        raise exc
    raise ModelRetry(retry_message) from exc


def _build_retry_message(tool_name: str, exc: Exception) -> str | None:
    if isinstance(exc, FileNotOpenError):
        return (
            f"{tool_name} requires an open Lean file session. "
            "Call open(path=...) for that Lean file first, then retry the original query."
        )
    if isinstance(exc, FileChangedError):
        return (
            f"{tool_name} cannot use the current Lean session because the file changed on disk. "
            "Call open(path=...) again to reopen the file, then retry."
        )
    if isinstance(exc, StaleNodeError):
        return (
            f"{tool_name} was given a stale or unknown Lean node id. "
            "Call load_node(path=..., line=..., col=...) again to get a fresh node id, then retry."
        )
    if isinstance(exc, WorkerUnavailableError):
        return (
            f"{tool_name} cannot use the current Lean worker session because it is unavailable. "
            "Call open(path=...) to start a fresh session, then retry."
        )
    if isinstance(exc, TacticFailedError):
        return (
            f"{tool_name} failed because Lean rejected that tactic: {_error_summary(exc)}. "
            "Inspect the current goals and try a different tactic or refresh the node first."
        )
    if isinstance(exc, InvalidParamsError):
        return f"{tool_name} rejected the arguments: {_error_summary(exc)}. Fix the arguments and retry."
    if isinstance(exc, DomainNotFoundError):
        return (
            f"{tool_name} could not find the requested item: {_error_summary(exc)}. "
            "Check the referenced id, root, modules, or filters and retry."
        )
    if isinstance(exc, DomainValidationError):
        return f"{tool_name} rejected the request: {_error_summary(exc)}. Adjust the arguments and retry."
    if isinstance(exc, (DomainConflictError, DomainOperationError)):
        return (
            f"{tool_name} could not complete the request: {_error_summary(exc)}. "
            "Choose a different valid action or adjust the arguments and retry."
        )
    if isinstance(exc, RequestTimeoutError):
        return (
            f"{tool_name} timed out: {_error_summary(exc)}. "
            "Retry with a smaller request or choose a different tool if that would make progress."
        )
    if isinstance(exc, FileExistsError):
        return (
            f"{tool_name} could not write because the destination file already exists: {_error_summary(exc)}. "
            "Choose a different path or set overwrite=true and retry."
        )
    if isinstance(exc, FileNotFoundError):
        return (
            f"{tool_name} could not find that file: {_error_summary(exc)}. "
            "Check the path first, then retry."
        )
    if isinstance(exc, (IsADirectoryError, NotADirectoryError)):
        return (
            f"{tool_name} was given the wrong kind of path: {_error_summary(exc)}. "
            "Choose the correct file or directory path and retry."
        )
    if isinstance(exc, CodingSandboxError):
        return (
            f"{tool_name} cannot access that path because it escapes the project sandbox: {_error_summary(exc)}. "
            "Choose a path inside the project root and retry."
        )
    if isinstance(exc, CodingPermissionError):
        return (
            f"{tool_name} cannot access that reserved framework path: {_error_summary(exc)}. "
            "Avoid .aftk/ and other reserved paths, then retry."
        )
    if isinstance(exc, EditConflictError):
        return (
            f"{tool_name} could not apply the requested edit safely: {_error_summary(exc)}. "
            "Read the file again, update the exact text or context, and retry."
        )
    if isinstance(exc, (ValueError, CodingError)):
        return f"{tool_name} rejected the request: {_error_summary(exc)}. Fix the arguments or choose a different target and retry."
    if isinstance(exc, DomainRequestError):
        return f"{tool_name} failed: {_error_summary(exc)}. Adjust the request and retry."
    if isinstance(exc, JsonRpcRequestError):
        return None
    return None


def _error_summary(exc: Exception) -> str:
    if isinstance(exc, RequestTimeoutError):
        return str(exc)
    if isinstance(exc, DomainRequestError) and exc.domain is not None:
        return exc.domain.message
    if isinstance(exc, JsonRpcRequestError):
        if isinstance(exc.data, str) and exc.data:
            return f"{exc.message} ({exc.data})"
        return exc.message
    text = str(exc).strip()
    return text or exc.__class__.__name__


__all__ = ["wrap_async_tool_errors", "wrap_tool_errors"]
