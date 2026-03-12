from __future__ import annotations

import asyncio
import json
import logging
import os
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping

from pydantic import ValidationError

from aftk.errors import ProtocolError, RequestTimeoutError, TransportClosedError
from aftk.jsonrpc import JsonRpcErrorResponse, JsonRpcRequest, JsonRpcSuccessResponse


logger = logging.getLogger(__name__)


@dataclass(slots=True)
class PendingRequest:
    method: str
    future: asyncio.Future[JsonRpcSuccessResponse | JsonRpcErrorResponse]


class AsyncJsonRpcSubprocessTransport:
    def __init__(
        self,
        *,
        command: tuple[str, ...],
        cwd: Path | None,
        env: Mapping[str, str] | None = None,
        shutdown_timeout: float = 5.0,
        exit_timeout: float = 5.0,
        terminate_timeout: float = 2.0,
    ) -> None:
        self._command = command
        self._cwd = cwd
        self._env = dict(os.environ) | dict(env or {})
        self._shutdown_timeout = shutdown_timeout
        self._exit_timeout = exit_timeout
        self._terminate_timeout = terminate_timeout

        self._process: asyncio.subprocess.Process | None = None
        self._reader_task: asyncio.Task[None] | None = None
        self._stderr_task: asyncio.Task[None] | None = None
        self._write_lock = asyncio.Lock()
        self._lifecycle_lock = asyncio.Lock()
        self._pending: dict[int, PendingRequest] = {}
        self._next_request_id = 0
        self._closing = False
        self._closed = False
        self._fatal_error: Exception | None = None
        self._stderr_tail: deque[str] = deque(maxlen=200)

    @property
    def cwd(self) -> Path | None:
        return self._cwd

    @property
    def stderr_tail(self) -> tuple[str, ...]:
        return tuple(self._stderr_tail)

    @property
    def is_started(self) -> bool:
        return self._process is not None and self._process.returncode is None

    async def start(self) -> None:
        async with self._lifecycle_lock:
            if self._closed:
                raise TransportClosedError("transport is already closed")
            if self.is_started:
                return
            if not self._command:
                raise TransportClosedError("cannot start transport without a command")

            self._process = await asyncio.create_subprocess_exec(
                *self._command,
                cwd=str(self._cwd) if self._cwd is not None else None,
                env=self._env,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            self._closing = False
            self._fatal_error = None
            self._reader_task = asyncio.create_task(self._reader_loop(), name="aftk-client-stdout")
            self._stderr_task = asyncio.create_task(self._stderr_loop(), name="aftk-client-stderr")

    async def request(
        self,
        method: str,
        params: dict[str, Any],
        *,
        timeout: float | None = None,
        allow_during_close: bool = False,
    ) -> tuple[int, JsonRpcSuccessResponse | JsonRpcErrorResponse]:
        await self.start()
        if self._fatal_error is not None:
            raise TransportClosedError(f"transport is in a failed state: {self._fatal_error}") from self._fatal_error
        if self._closing and not allow_during_close:
            raise TransportClosedError("transport is closing")

        process = self._require_process()
        stdin = process.stdin
        if stdin is None:
            raise TransportClosedError("server stdin is unavailable")

        request_id = self._next_request_id
        self._next_request_id += 1

        payload = JsonRpcRequest(id=request_id, method=method, params=params)
        encoded = json.dumps(payload.model_dump(by_alias=True, exclude_none=True), separators=(",", ":")) + "\n"

        loop = asyncio.get_running_loop()
        future: asyncio.Future[JsonRpcSuccessResponse | JsonRpcErrorResponse] = loop.create_future()
        self._pending[request_id] = PendingRequest(method=method, future=future)

        try:
            async with self._write_lock:
                if process.returncode is not None:
                    raise TransportClosedError(f"server process exited with code {process.returncode}")
                stdin.write(encoded.encode("utf-8"))
                await stdin.drain()
        except Exception as exc:
            self._pending.pop(request_id, None)
            error = exc if isinstance(exc, TransportClosedError) else TransportClosedError(
                f"failed to write request {method!r}: {exc}"
            )
            if not future.done():
                future.set_exception(error)
            raise error from exc

        try:
            waiter = asyncio.shield(future)
            if timeout is None:
                response = await waiter
            else:
                response = await asyncio.wait_for(waiter, timeout=timeout)
        except asyncio.CancelledError:
            asyncio.create_task(self._discard_future(future))
            raise
        except asyncio.TimeoutError as exc:
            asyncio.create_task(self._discard_future(future))
            assert timeout is not None
            raise RequestTimeoutError(method=method, request_id=request_id, timeout=timeout) from exc

        return request_id, response

    async def aclose(self) -> None:
        async with self._lifecycle_lock:
            if self._closed:
                return
            self._closing = True
            process = self._process
            reader_task = self._reader_task
            stderr_task = self._stderr_task

        if process is None:
            async with self._lifecycle_lock:
                self._closed = True
            return

        if process.returncode is None and reader_task is not None and not reader_task.done():
            try:
                await self.request("shutdown", {}, timeout=self._shutdown_timeout, allow_during_close=True)
            except Exception:
                logger.debug("best-effort shutdown request failed", exc_info=True)

        await self._close_stdin()

        try:
            await asyncio.wait_for(process.wait(), timeout=self._exit_timeout)
        except asyncio.TimeoutError:
            logger.debug("server did not exit after stdin close; terminating")
            process.terminate()
            try:
                await asyncio.wait_for(process.wait(), timeout=self._terminate_timeout)
            except asyncio.TimeoutError:
                logger.debug("server did not terminate promptly; killing")
                process.kill()
                await process.wait()

        self._fail_all_pending(TransportClosedError("transport closed"))

        await self._await_background_task(reader_task)
        await self._await_background_task(stderr_task)

        async with self._lifecycle_lock:
            self._closed = True
            self._process = None
            self._reader_task = None
            self._stderr_task = None

    async def _close_stdin(self) -> None:
        process = self._process
        if process is None or process.stdin is None:
            return
        try:
            process.stdin.close()
            await process.stdin.wait_closed()
        except Exception:
            logger.debug("failed to close stdin cleanly", exc_info=True)

    async def _await_background_task(self, task: asyncio.Task[None] | None) -> None:
        if task is None:
            return
        if not task.done():
            task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass
        except Exception:
            logger.debug("background transport task exited with error", exc_info=True)

    async def _reader_loop(self) -> None:
        try:
            process = self._require_process()
            stdout = process.stdout
            if stdout is None:
                raise TransportClosedError("server stdout is unavailable")

            while True:
                line = await stdout.readline()
                if not line:
                    if self._closing:
                        break
                    raise TransportClosedError(self._build_closed_message("server stdout reached EOF"))

                message = line.decode("utf-8", errors="replace").strip()
                if not message:
                    continue

                response = self._parse_response_message(message)
                request_id = response.id
                if request_id is None:
                    raise ProtocolError(f"received error response without an id: {message}")

                pending = self._pending.pop(request_id, None)
                if pending is None:
                    raise ProtocolError(f"received response for unknown request id {request_id}: {message}")

                if not pending.future.done():
                    pending.future.set_result(response)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            self._fatal_error = exc
            self._fail_all_pending(exc)
        finally:
            if self._process is not None and self._process.returncode is not None:
                self._fail_all_pending(
                    TransportClosedError(
                        self._build_closed_message(
                            f"server process exited with code {self._process.returncode}"
                        )
                    )
                )

    async def _stderr_loop(self) -> None:
        process = self._process
        if process is None or process.stderr is None:
            return

        try:
            while True:
                line = await process.stderr.readline()
                if not line:
                    return
                text = line.decode("utf-8", errors="replace").rstrip()
                self._stderr_tail.append(text)
                logger.debug("aftk_server stderr: %s", text)
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.debug("stderr reader failed", exc_info=True)

    def _parse_response_message(self, message: str) -> JsonRpcSuccessResponse | JsonRpcErrorResponse:
        try:
            payload = json.loads(message)
        except json.JSONDecodeError as exc:
            raise ProtocolError(f"invalid JSON response line: {exc}: {message}") from exc

        if not isinstance(payload, dict):
            raise ProtocolError(f"response is not a JSON object: {message}")

        has_result = "result" in payload
        has_error = "error" in payload
        if has_result == has_error:
            raise ProtocolError(f"response must contain exactly one of 'result' or 'error': {message}")

        model = JsonRpcSuccessResponse if has_result else JsonRpcErrorResponse
        try:
            return model.model_validate(payload)
        except ValidationError as exc:
            raise ProtocolError(f"invalid JSON-RPC response envelope: {exc}") from exc

    def _build_closed_message(self, prefix: str) -> str:
        if not self._stderr_tail:
            return prefix
        tail = "\n".join(self._stderr_tail)
        return f"{prefix}\nserver stderr tail:\n{tail}"

    def _fail_all_pending(self, exc: Exception) -> None:
        pending_items = list(self._pending.items())
        self._pending.clear()
        for _, pending in pending_items:
            if not pending.future.done():
                pending.future.set_exception(exc)

    async def _discard_future(
        self, future: asyncio.Future[JsonRpcSuccessResponse | JsonRpcErrorResponse]
    ) -> None:
        try:
            await future
        except Exception:
            return

    def _require_process(self) -> asyncio.subprocess.Process:
        if self._process is None:
            raise TransportClosedError("transport process is not started")
        return self._process
