from __future__ import annotations

from typing import Any, Literal

from pydantic import Field

from aftk_client.models import RequestModel, ResponseModel


class JsonRpcRequest(RequestModel):
    jsonrpc: Literal["2.0"] = "2.0"
    id: int
    method: str
    params: dict[str, Any] = Field(default_factory=dict)


class JsonRpcErrorObject(ResponseModel):
    code: int
    message: str
    data: Any | None = None


class JsonRpcSuccessResponse(ResponseModel):
    jsonrpc: Literal["2.0"]
    id: int
    result: Any


class JsonRpcErrorResponse(ResponseModel):
    jsonrpc: Literal["2.0"]
    id: int | None
    error: JsonRpcErrorObject
