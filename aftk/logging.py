from __future__ import annotations

import json
import logging
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Literal

from pydantic_ai import FinalResultEvent, FunctionToolCallEvent, FunctionToolResultEvent, PartDeltaEvent, PartStartEvent
from pydantic_ai.messages import RetryPromptPart, TextPart, TextPartDelta, ThinkingPart, ThinkingPartDelta, ToolCallPart, ToolCallPartDelta, ToolReturnPart

from aftk.config import FrameworkConfig


LogLevelName = Literal["critical", "error", "warning", "info", "debug"]
PayloadMode = Literal["none", "summary", "full"]
TraceModelEventsMode = Literal["off", "summary", "full"]


@dataclass(slots=True)
class LoggingCliConfig:
    level: str = "info"
    console: bool = True
    file: bool = True
    file_path: str = ".aftk/cli.log"
    file_format: str = "text"
    dependency_level: str = "warning"
    include_http: bool = False
    include_llm_payloads: bool = False
    include_tool_payloads: str = "summary"
    include_command_output: str = "summary"
    live_traces: bool = True
    trace_model_events: str = "summary"
    trace_tool_events: bool = True
    trace_thinking_deltas: bool = False
    structured_events: bool = True
    structured_event_path: str = ".aftk/events.jsonl"


@dataclass(slots=True)
class LoggingRuntime:
    config: LoggingCliConfig
    project_root: Path
    log_path: Path | None
    structured_event_path: Path | None
    handlers: list[logging.Handler]

    def close(self) -> None:
        root = logging.getLogger()
        for handler in self.handlers:
            root.removeHandler(handler)
            handler.close()

    def create_agent_event_stream_handler(
        self,
        *,
        run_id: str,
        agent_role: str,
        task_id: str | None,
        attempt_id: str | None,
        model_name: str | None,
    ):
        if not self.config.live_traces:
            return None

        logger = logging.getLogger("aftk.trace")
        base_context = {
            "run_id": run_id,
            "agent_role": agent_role,
            "task_id": task_id,
            "attempt_id": attempt_id,
            "model_name": model_name,
        }

        async def handle_event_stream(ctx: Any, events: Any) -> None:
            del ctx
            async for event in events:
                if isinstance(event, FunctionToolCallEvent):
                    if not self.config.trace_tool_events:
                        continue
                    log_event(
                        logger,
                        logging.INFO,
                        "tool_start",
                        f"tool_start {event.part.tool_name}",
                        tool_name=event.part.tool_name,
                        tool_call_id=event.part.tool_call_id,
                        tool_args=_render_payload(event.part.args, mode=self.config.include_tool_payloads),
                        args_valid=event.args_valid,
                        **base_context,
                    )
                    continue

                if isinstance(event, FunctionToolResultEvent):
                    result = event.result
                    if isinstance(result, RetryPromptPart):
                        if not self.config.trace_tool_events:
                            continue
                        log_event(
                            logger,
                            logging.WARNING,
                            "tool_retry",
                            f"tool_retry {result.tool_name or '(unknown)'}",
                            tool_name=result.tool_name,
                            tool_call_id=result.tool_call_id,
                            retry_reason=_render_payload(result.content, mode="summary"),
                            **base_context,
                        )
                        continue

                    if not self.config.trace_tool_events:
                        continue
                    log_event(
                        logger,
                        logging.INFO if result.outcome == "success" else logging.WARNING,
                        "tool_end",
                        f"tool_end {result.tool_name}",
                        tool_name=result.tool_name,
                        tool_call_id=result.tool_call_id,
                        status=result.outcome,
                        output=_render_payload(result.content, mode=self.config.include_tool_payloads),
                        **base_context,
                    )
                    continue

                if isinstance(event, FinalResultEvent):
                    log_event(
                        logger,
                        logging.INFO,
                        "final_result",
                        "model produced final result",
                        tool_name=event.tool_name,
                        tool_call_id=event.tool_call_id,
                        **base_context,
                    )
                    continue

                if isinstance(event, PartStartEvent):
                    self._log_part_start(logger, event, base_context)
                    continue

                if isinstance(event, PartDeltaEvent):
                    self._log_part_delta(logger, event, base_context)

        return handle_event_stream

    def _log_part_start(self, logger: logging.Logger, event: PartStartEvent, context: dict[str, Any]) -> None:
        mode = _normalize_trace_model_events(self.config.trace_model_events)
        if mode == "off":
            return
        part = event.part
        if isinstance(part, ToolCallPart):
            return
        if isinstance(part, ThinkingPart) and not self.config.trace_thinking_deltas and mode != "full":
            log_event(
                logger,
                logging.DEBUG,
                "model_part_start",
                "model part started",
                part_kind=part.part_kind,
                **context,
            )
            return
        payload = _part_payload(part, include_llm_payloads=self.config.include_llm_payloads, mode=mode)
        log_event(
            logger,
            logging.DEBUG if mode == "full" else logging.INFO,
            "model_part_start",
            "model part started",
            part_kind=part.part_kind,
            payload=payload,
            **context,
        )

    def _log_part_delta(self, logger: logging.Logger, event: PartDeltaEvent, context: dict[str, Any]) -> None:
        mode = _normalize_trace_model_events(self.config.trace_model_events)
        if mode != "full":
            return
        delta = event.delta
        if isinstance(delta, ThinkingPartDelta) and not self.config.trace_thinking_deltas:
            return
        payload = _delta_payload(delta, include_llm_payloads=self.config.include_llm_payloads)
        if payload is None:
            return
        log_event(
            logger,
            logging.DEBUG,
            "model_part_delta",
            "model part delta",
            part_kind=getattr(delta, "part_delta_kind", None),
            payload=payload,
            **context,
        )


class ContextFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        rendered = super().format(record)
        context_parts: list[str] = []
        for key in _CONTEXT_FIELDS:
            value = getattr(record, key, None)
            if value is None:
                continue
            context_parts.append(f"{key}={_format_context_value(value)}")
        if context_parts:
            rendered = f"{rendered} {' '.join(context_parts)}"
        return rendered


class JsonlEventHandler(logging.Handler):
    def __init__(self, path: Path) -> None:
        super().__init__()
        self.path = path

    def emit(self, record: logging.LogRecord) -> None:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            payload: dict[str, Any] = {
                "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
                "level": record.levelname.lower(),
                "logger": record.name,
                "message": record.getMessage(),
            }
            for key in _CONTEXT_FIELDS:
                value = getattr(record, key, None)
                if value is not None:
                    payload[key] = value
            if record.exc_info is not None:
                formatter = self.formatter if isinstance(self.formatter, logging.Formatter) else logging.Formatter()
                payload["exception"] = formatter.formatException(record.exc_info)
            with self.path.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(payload, ensure_ascii=False, default=_json_default))
                handle.write("\n")
        except Exception:
            self.handleError(record)


def setup_logging(config: LoggingCliConfig, framework_config: FrameworkConfig) -> LoggingRuntime:
    config.file_format = _normalize_file_format(config.file_format)
    config.include_tool_payloads = _normalize_payload_mode(config.include_tool_payloads)
    config.include_command_output = _normalize_payload_mode(config.include_command_output)
    config.trace_model_events = _normalize_trace_model_events(config.trace_model_events)

    root = logging.getLogger()
    for handler in list(root.handlers):
        root.removeHandler(handler)
        handler.close()
    root.setLevel(logging.DEBUG)

    normalized_level = _normalize_log_level(config.level)
    handlers: list[logging.Handler] = []
    formatter = ContextFormatter(fmt="%(asctime)s %(levelname)s %(name)s %(message)s", datefmt="%Y-%m-%d %H:%M:%S")

    log_path = _resolve_log_path(framework_config, config.file_path) if config.file else None
    if config.console:
        console_handler = logging.StreamHandler(sys.stderr)
        console_handler.setLevel(normalized_level)
        console_handler.setFormatter(formatter)
        root.addHandler(console_handler)
        handlers.append(console_handler)
    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        file_handler = logging.FileHandler(log_path, encoding="utf-8")
        file_handler.setLevel(normalized_level)
        file_handler.setFormatter(formatter)
        root.addHandler(file_handler)
        handlers.append(file_handler)

    structured_event_path = _resolve_log_path(framework_config, config.structured_event_path) if config.structured_events else None
    if structured_event_path is not None:
        structured_handler = JsonlEventHandler(structured_event_path)
        structured_handler.setLevel(normalized_level)
        root.addHandler(structured_handler)
        handlers.append(structured_handler)

    dependency_level = _normalize_log_level(config.dependency_level)
    for name in ("httpx", "httpcore", "openai"):
        logging.getLogger(name).setLevel(dependency_level if config.include_http else logging.WARNING)
    logging.getLogger("asyncio").setLevel(dependency_level)
    logging.getLogger("aftk").setLevel(logging.DEBUG)
    logging.captureWarnings(True)

    return LoggingRuntime(
        config=config,
        project_root=framework_config.paths.project_root,
        log_path=log_path,
        structured_event_path=structured_event_path,
        handlers=handlers,
    )


def log_event(logger: logging.Logger, level: int, event_type: str, message: str, **context: Any) -> None:
    payload = {"event_type": event_type}
    payload.update({key: value for key, value in context.items() if value is not None})
    logger.log(level, message, extra=payload)


def _normalize_log_level(value: str) -> int:
    normalized = value.strip().lower()
    mapping = {
        "critical": logging.CRITICAL,
        "error": logging.ERROR,
        "warning": logging.WARNING,
        "warn": logging.WARNING,
        "info": logging.INFO,
        "debug": logging.DEBUG,
    }
    if normalized not in mapping:
        raise ValueError(f"unsupported logging level: {value!r}")
    return mapping[normalized]


def _normalize_trace_model_events(value: str) -> TraceModelEventsMode:
    normalized = value.strip().lower()
    if normalized not in {"off", "summary", "full"}:
        raise ValueError(f"unsupported trace_model_events value: {value!r}")
    return normalized  # type: ignore[return-value]


def _normalize_payload_mode(value: str) -> PayloadMode:
    normalized = value.strip().lower()
    if normalized not in {"none", "summary", "full"}:
        raise ValueError(f"unsupported payload mode: {value!r}")
    return normalized  # type: ignore[return-value]


def _normalize_file_format(value: str) -> str:
    normalized = value.strip().lower()
    if normalized != "text":
        raise ValueError(f"unsupported logging file_format: {value!r}")
    return normalized


def _resolve_log_path(framework_config: FrameworkConfig, path_value: str) -> Path:
    candidate = Path(path_value).expanduser()
    if not candidate.is_absolute():
        candidate = framework_config.paths.project_root / candidate
    return candidate.resolve(strict=False)


def _part_payload(part: Any, *, include_llm_payloads: bool, mode: TraceModelEventsMode) -> str | None:
    if isinstance(part, TextPart):
        if not include_llm_payloads:
            return None
        return _render_payload(part.content, mode="full" if mode == "full" else "summary")
    if isinstance(part, ThinkingPart):
        if not include_llm_payloads:
            return None
        return _render_payload(getattr(part, "content", None), mode="full" if mode == "full" else "summary")
    return None


def _delta_payload(delta: Any, *, include_llm_payloads: bool) -> str | None:
    if isinstance(delta, TextPartDelta):
        if not include_llm_payloads:
            return None
        return _render_payload(delta.content_delta, mode="summary")
    if isinstance(delta, ThinkingPartDelta):
        if not include_llm_payloads:
            return None
        return _render_payload(delta.content_delta, mode="summary")
    if isinstance(delta, ToolCallPartDelta):
        return _render_payload(
            {
                "tool_name_delta": delta.tool_name_delta,
                "args_delta": delta.args_delta,
                "tool_call_id": delta.tool_call_id,
            },
            mode="summary",
        )
    return None


def _render_payload(value: Any, *, mode: str) -> str | None:
    if mode == "none":
        return None
    compact = _compact_value(value)
    rendered = json.dumps(compact, ensure_ascii=False, default=_json_default)
    if mode == "summary":
        return _truncate(rendered, limit=240)
    return rendered


def _compact_value(value: Any) -> Any:
    if value is None or isinstance(value, (int, float, bool)):
        return value
    if isinstance(value, str):
        return _truncate(value, limit=240)
    if isinstance(value, dict):
        items = list(value.items())
        compact = {str(key): _compact_value(item) for key, item in items[:12]}
        if len(items) > 12:
            compact["..."] = f"+{len(items) - 12} more"
        return compact
    if isinstance(value, (list, tuple)):
        preview = [_compact_value(item) for item in list(value)[:12]]
        if len(value) > 12:
            preview.append(f"... (+{len(value) - 12} more)")
        return preview
    if isinstance(value, ToolReturnPart):
        return {
            "tool_name": value.tool_name,
            "outcome": value.outcome,
            "content": _compact_value(value.content),
        }
    if isinstance(value, RetryPromptPart):
        return {
            "tool_name": value.tool_name,
            "content": _compact_value(value.content),
        }
    return _truncate(str(value), limit=240)


def _truncate(value: str, *, limit: int = 200) -> str:
    if len(value) <= limit:
        return value
    return f"{value[: limit - 3]}..."


def _format_context_value(value: Any) -> str:
    if isinstance(value, str):
        if any(character.isspace() for character in value):
            return json.dumps(_truncate(value, limit=240), ensure_ascii=False)
        return _truncate(value, limit=240)
    if isinstance(value, (int, float, bool)):
        return str(value)
    return json.dumps(_compact_value(value), ensure_ascii=False, default=_json_default)


def _json_default(value: Any) -> Any:
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


_CONTEXT_FIELDS = (
    "event_type",
    "run_id",
    "agent_role",
    "task_id",
    "attempt_id",
    "model_name",
    "tool_name",
    "tool_call_id",
    "part_kind",
    "status",
    "duration_s",
    "revision",
    "args_valid",
    "tool_args",
    "output",
    "payload",
    "retry_reason",
    "project_root",
    "state_dir",
    "max_iterations",
    "selected_task_id",
    "new_tasks",
    "patches",
    "worker_kind",
    "command",
    "cwd",
    "exit_code",
    "timed_out",
    "stdout_preview",
    "stderr_preview",
    "artifact_dir",
    "summary",
    "reason",
)


__all__ = ["LoggingCliConfig", "LoggingRuntime", "log_event", "setup_logging"]
