from __future__ import annotations

from dataclasses import dataclass
from typing import Any


class AftkClientError(Exception):
    """Base exception for the Python AFTK client."""


class ConfigurationError(AftkClientError):
    """Client configuration is invalid or incomplete."""


class ProjectRootNotFoundError(ConfigurationError):
    """A Lake project root could not be inferred from a path."""


class InvalidProjectRootError(ConfigurationError):
    """A provided project root does not look like a Lake project."""


class ClientNotStartedError(AftkClientError):
    """The client transport has not been started yet."""


class TransportClosedError(AftkClientError):
    """The JSON-RPC transport is closed or unavailable."""


class ProtocolError(AftkClientError):
    """The server produced an invalid or uncorrelatable JSON-RPC response."""


@dataclass(slots=True)
class ResponseDecodeContext:
    method: str
    request_id: int
    result_type: str


class ResponseDecodeError(AftkClientError):
    """A JSON-RPC success payload could not be decoded into the expected model."""

    def __init__(self, message: str, *, context: ResponseDecodeContext, raw_result: Any) -> None:
        super().__init__(message)
        self.context = context
        self.raw_result = raw_result


class RequestTimeoutError(AftkClientError):
    """A request did not receive a response within the configured timeout."""

    def __init__(self, *, method: str, request_id: int, timeout: float) -> None:
        super().__init__(f"request {method!r} (id={request_id}) timed out after {timeout:.3f}s")
        self.method = method
        self.request_id = request_id
        self.timeout = timeout


@dataclass(slots=True)
class DomainErrorData:
    layer: str
    code: str
    message: str
    exit_code: int


class JsonRpcRequestError(AftkClientError):
    """A JSON-RPC error response returned by the AFTK server."""

    def __init__(
        self,
        *,
        code: int,
        message: str,
        data: Any,
        method: str,
        request_id: int,
    ) -> None:
        super().__init__(f"{method} failed with JSON-RPC error {code}: {message}")
        self.code = code
        self.message = message
        self.data = data
        self.method = method
        self.request_id = request_id


class InvalidParamsError(JsonRpcRequestError):
    pass


class InternalJsonRpcError(JsonRpcRequestError):
    pass


class TacticFailedError(JsonRpcRequestError):
    pass


class FileNotOpenError(JsonRpcRequestError):
    pass


class FileChangedError(JsonRpcRequestError):
    pass


class WorkerUnavailableError(JsonRpcRequestError):
    pass


class StaleNodeError(JsonRpcRequestError):
    pass


class DomainRequestError(JsonRpcRequestError):
    def __init__(
        self,
        *,
        code: int,
        message: str,
        data: Any,
        method: str,
        request_id: int,
    ) -> None:
        super().__init__(code=code, message=message, data=data, method=method, request_id=request_id)
        self.domain = decode_domain_error_data(data)


class DomainNotFoundError(DomainRequestError):
    pass


class DomainValidationError(DomainRequestError):
    pass


class DomainConflictError(DomainRequestError):
    pass


class DomainOperationError(DomainRequestError):
    pass


_ERROR_CODE_MAP: dict[int, type[JsonRpcRequestError]] = {
    -32602: InvalidParamsError,
    -32603: InternalJsonRpcError,
    -32001: TacticFailedError,
    -32010: FileNotOpenError,
    -32011: FileChangedError,
    -32012: WorkerUnavailableError,
    -32013: StaleNodeError,
    -32020: DomainNotFoundError,
    -32021: DomainValidationError,
    -32022: DomainConflictError,
    -32023: DomainOperationError,
}


def decode_domain_error_data(data: Any) -> DomainErrorData | None:
    if not isinstance(data, dict):
        return None
    layer = data.get("layer")
    code = data.get("code")
    message = data.get("message")
    exit_code = data.get("exitCode")
    if not isinstance(layer, str) or not isinstance(code, str) or not isinstance(message, str):
        return None
    if not isinstance(exit_code, int):
        return None
    return DomainErrorData(layer=layer, code=code, message=message, exit_code=exit_code)


def jsonrpc_error_from_response(
    *, code: int, message: str, data: Any, method: str, request_id: int
) -> JsonRpcRequestError:
    exc_type = _ERROR_CODE_MAP.get(code, JsonRpcRequestError)
    return exc_type(code=code, message=message, data=data, method=method, request_id=request_id)
