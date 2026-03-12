from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from aftk.errors import (
    AftkClientError,
    ClientNotStartedError,
    ConfigurationError,
    DomainConflictError,
    DomainNotFoundError,
    DomainOperationError,
    DomainRequestError,
    DomainValidationError,
    FileChangedError,
    FileNotOpenError,
    InternalJsonRpcError,
    InvalidParamsError,
    InvalidProjectRootError,
    JsonRpcRequestError,
    ProjectRootNotFoundError,
    ProtocolError,
    RequestTimeoutError,
    ResponseDecodeError,
    StaleNodeError,
    TacticFailedError,
    TransportClosedError,
    WorkerUnavailableError,
)

from .models import AftkToolErrorInfo, AftkToolFailure


@dataclass(slots=True)
class AftkToolkitExecutionError(Exception):
    """Internal exception used for expected toolkit-level failures."""

    kind: str
    message: str
    retryable: bool
    suggested_action: str | None = None
    details: dict[str, Any] | None = None

    def __post_init__(self) -> None:
        Exception.__init__(self, self.message)


def failure_from_exception(tool_name: str, exc: AftkClientError | AftkToolkitExecutionError) -> AftkToolFailure:
    """Convert an expected client or toolkit failure into a structured tool result."""

    return AftkToolFailure(tool=tool_name, error=error_info_from_exception(exc))


def error_info_from_exception(exc: AftkClientError | AftkToolkitExecutionError) -> AftkToolErrorInfo:
    """Map a client or toolkit exception to an agent-facing error payload."""

    if isinstance(exc, AftkToolkitExecutionError):
        return AftkToolErrorInfo(
            kind=exc.kind,
            message=exc.message,
            retryable=exc.retryable,
            suggested_action=exc.suggested_action,
            details=exc.details,
        )

    if isinstance(exc, InvalidParamsError):
        return _jsonrpc_error_info(exc, kind="invalid_params", retryable=True, suggested_action="fix_arguments")
    if isinstance(exc, TacticFailedError):
        return _jsonrpc_error_info(
            exc,
            kind="tactic_failed",
            retryable=True,
            suggested_action="try_different_tactic",
        )
    if isinstance(exc, FileNotOpenError):
        return _jsonrpc_error_info(exc, kind="file_not_open", retryable=True, suggested_action="open_file")
    if isinstance(exc, FileChangedError):
        return _jsonrpc_error_info(exc, kind="file_changed", retryable=True, suggested_action="reopen_file")
    if isinstance(exc, WorkerUnavailableError):
        return _jsonrpc_error_info(exc, kind="worker_unavailable", retryable=True, suggested_action="retry")
    if isinstance(exc, StaleNodeError):
        return _jsonrpc_error_info(exc, kind="stale_node", retryable=True, suggested_action="reload_position")
    if isinstance(exc, DomainNotFoundError):
        return _domain_error_info(exc, kind="domain_not_found", retryable=False, suggested_action="check_id_or_create")
    if isinstance(exc, DomainValidationError):
        return _domain_error_info(exc, kind="domain_validation", retryable=True, suggested_action="fix_request")
    if isinstance(exc, DomainConflictError):
        return _domain_error_info(exc, kind="domain_conflict", retryable=True, suggested_action="choose_different_id")
    if isinstance(exc, DomainOperationError):
        return _domain_error_info(exc, kind="domain_operation", retryable=False, suggested_action="inspect_details")
    if isinstance(exc, InternalJsonRpcError):
        return _jsonrpc_error_info(
            exc,
            kind="internal_jsonrpc_error",
            retryable=False,
            suggested_action="report_failure",
        )
    if isinstance(exc, DomainRequestError):
        return _domain_error_info(exc, kind="domain_request", retryable=False, suggested_action="inspect_details")
    if isinstance(exc, JsonRpcRequestError):
        return _jsonrpc_error_info(exc, kind="jsonrpc_error", retryable=False, suggested_action="inspect_details")
    if isinstance(exc, RequestTimeoutError):
        return AftkToolErrorInfo(
            kind="timeout",
            message=str(exc),
            retryable=True,
            suggested_action="retry",
            details={
                "method": exc.method,
                "request_id": exc.request_id,
                "timeout": exc.timeout,
            },
        )
    if isinstance(exc, TransportClosedError):
        return AftkToolErrorInfo(
            kind="transport_closed",
            message=str(exc),
            retryable=True,
            suggested_action="retry",
        )
    if isinstance(exc, ProtocolError):
        return AftkToolErrorInfo(
            kind="protocol_error",
            message=str(exc),
            retryable=False,
            suggested_action="report_failure",
        )
    if isinstance(exc, ResponseDecodeError):
        return AftkToolErrorInfo(
            kind="response_decode_error",
            message=str(exc),
            retryable=False,
            suggested_action="report_failure",
            details={
                "method": exc.context.method,
                "request_id": exc.context.request_id,
                "result_type": exc.context.result_type,
                "raw_result": exc.raw_result,
            },
        )
    if isinstance(exc, ProjectRootNotFoundError):
        return AftkToolErrorInfo(
            kind="project_root_not_found",
            message=str(exc),
            retryable=False,
            suggested_action="set_project_root",
        )
    if isinstance(exc, InvalidProjectRootError):
        return AftkToolErrorInfo(
            kind="invalid_project_root",
            message=str(exc),
            retryable=False,
            suggested_action="check_project_root",
        )
    if isinstance(exc, ConfigurationError):
        return AftkToolErrorInfo(
            kind="configuration_error",
            message=str(exc),
            retryable=False,
            suggested_action="report_failure",
        )
    if isinstance(exc, ClientNotStartedError):
        return AftkToolErrorInfo(
            kind="client_not_started",
            message=str(exc),
            retryable=True,
            suggested_action="retry",
        )

    return AftkToolErrorInfo(
        kind="aftk_client_error",
        message=str(exc),
        retryable=False,
        suggested_action="report_failure",
    )


def _jsonrpc_error_info(
    exc: JsonRpcRequestError,
    *,
    kind: str,
    retryable: bool,
    suggested_action: str | None,
) -> AftkToolErrorInfo:
    details = {
        "jsonrpc_code": exc.code,
        "method": exc.method,
        "request_id": exc.request_id,
    }
    if exc.data is not None:
        details["data"] = exc.data

    return AftkToolErrorInfo(
        kind=kind,
        message=exc.message,
        retryable=retryable,
        suggested_action=suggested_action,
        details=details,
    )


def _domain_error_info(
    exc: DomainRequestError,
    *,
    kind: str,
    retryable: bool,
    suggested_action: str | None,
) -> AftkToolErrorInfo:
    details = {
        "jsonrpc_code": exc.code,
        "method": exc.method,
        "request_id": exc.request_id,
    }
    if exc.data is not None:
        details["data"] = exc.data
    if exc.domain is not None:
        details.update(
            {
                "domain_layer": exc.domain.layer,
                "domain_code": exc.domain.code,
                "domain_message": exc.domain.message,
                "domain_exit_code": exc.domain.exit_code,
            }
        )
        message = exc.domain.message
    else:
        message = exc.message

    return AftkToolErrorInfo(
        kind=kind,
        message=message,
        retryable=retryable,
        suggested_action=suggested_action,
        details=details,
    )
