from __future__ import annotations

from datetime import datetime, timezone
from enum import StrEnum
from typing import Annotated, Any

from pydantic import AwareDatetime, Field, model_validator

from aftk.config import FrameworkModel


NonEmptyString = Annotated[str, Field(min_length=1)]
TelemetryScalar = str | int | float | bool | None


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class UsageSummary(FrameworkModel):
    requests: int = Field(default=0, ge=0)
    tool_calls: int = Field(default=0, ge=0)
    input_tokens: int = Field(default=0, ge=0)
    cache_write_tokens: int = Field(default=0, ge=0)
    cache_read_tokens: int = Field(default=0, ge=0)
    output_tokens: int = Field(default=0, ge=0)
    input_audio_tokens: int = Field(default=0, ge=0)
    cache_audio_read_tokens: int = Field(default=0, ge=0)
    output_audio_tokens: int = Field(default=0, ge=0)
    details: dict[str, int] = Field(default_factory=dict)

    @property
    def total_tokens(self) -> int:
        return self.input_tokens + self.output_tokens

    def has_values(self) -> bool:
        return any(
            [
                self.requests,
                self.tool_calls,
                self.input_tokens,
                self.cache_write_tokens,
                self.cache_read_tokens,
                self.output_tokens,
                self.input_audio_tokens,
                self.cache_audio_read_tokens,
                self.output_audio_tokens,
                *self.details.values(),
            ]
        )

    def add(self, other: UsageSummary | object | None) -> UsageSummary:
        rhs = self.from_value(other)
        details = dict(self.details)
        for key, value in rhs.details.items():
            details[key] = details.get(key, 0) + value
        return UsageSummary(
            requests=self.requests + rhs.requests,
            tool_calls=self.tool_calls + rhs.tool_calls,
            input_tokens=self.input_tokens + rhs.input_tokens,
            cache_write_tokens=self.cache_write_tokens + rhs.cache_write_tokens,
            cache_read_tokens=self.cache_read_tokens + rhs.cache_read_tokens,
            output_tokens=self.output_tokens + rhs.output_tokens,
            input_audio_tokens=self.input_audio_tokens + rhs.input_audio_tokens,
            cache_audio_read_tokens=self.cache_audio_read_tokens + rhs.cache_audio_read_tokens,
            output_audio_tokens=self.output_audio_tokens + rhs.output_audio_tokens,
            details=details,
        )

    @classmethod
    def from_value(cls, value: UsageSummary | dict[str, object] | object | None) -> UsageSummary:
        if value is None:
            return cls()
        if isinstance(value, cls):
            return value
        if isinstance(value, dict):
            return cls.model_validate(value)

        data: dict[str, object] = {}
        for field_name in cls.model_fields:
            if hasattr(value, field_name):
                attribute = getattr(value, field_name)
                if attribute is not None:
                    data[field_name] = attribute
        return cls.model_validate(data)


class LlmCallStatus(StrEnum):
    SUCCEEDED = "succeeded"
    FAILED = "failed"


class ToolCallStatus(StrEnum):
    SUCCEEDED = "succeeded"
    FAILED = "failed"


class ToolFamily(StrEnum):
    TOOLKIT = "toolkit"
    PROJECT = "project"
    CODING = "coding"
    OTHER = "other"


class LlmCallRecord(FrameworkModel):
    index: int = Field(ge=1)
    run_id: NonEmptyString
    agent_role: NonEmptyString
    task_id: NonEmptyString | None = None
    attempt_id: NonEmptyString | None = None
    model_name: NonEmptyString | None = None
    started_at: AwareDatetime = Field(default_factory=utc_now)
    finished_at: AwareDatetime = Field(default_factory=utc_now)
    duration_seconds: float = Field(ge=0)
    status: LlmCallStatus
    usage: UsageSummary = Field(default_factory=UsageSummary)
    estimated_cost: float | None = Field(default=None, ge=0)
    request_summary: str | None = None
    response_summary: str | None = None
    error_message: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_timestamps(self) -> LlmCallRecord:
        if self.finished_at < self.started_at:
            raise ValueError("finished_at must not be earlier than started_at")
        if self.status is LlmCallStatus.FAILED and not self.error_message:
            raise ValueError("failed llm calls must include error_message")
        return self


class ToolCallRecord(FrameworkModel):
    index: int = Field(ge=1)
    run_id: NonEmptyString
    agent_role: NonEmptyString
    task_id: NonEmptyString | None = None
    attempt_id: NonEmptyString | None = None
    tool_name: NonEmptyString
    tool_family: ToolFamily = ToolFamily.OTHER
    started_at: AwareDatetime = Field(default_factory=utc_now)
    finished_at: AwareDatetime = Field(default_factory=utc_now)
    duration_seconds: float = Field(ge=0)
    status: ToolCallStatus
    input_summary: dict[str, Any] = Field(default_factory=dict)
    output_summary: dict[str, Any] = Field(default_factory=dict)
    error_message: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_timestamps(self) -> ToolCallRecord:
        if self.finished_at < self.started_at:
            raise ValueError("finished_at must not be earlier than started_at")
        if self.status is ToolCallStatus.FAILED and not self.error_message:
            raise ValueError("failed tool calls must include error_message")
        return self


def summarize_usage(
    llm_calls: list[LlmCallRecord],
    tool_calls: list[ToolCallRecord] | None = None,
) -> UsageSummary:
    aggregate = UsageSummary()
    request_count = 0
    tool_call_count = 0
    for call in llm_calls:
        call_usage = call.usage.model_copy(update={"requests": 0, "tool_calls": 0})
        aggregate = aggregate.add(call_usage)
        request_count += call.usage.requests or 1
        tool_call_count += call.usage.tool_calls

    successful_tool_calls = 0 if tool_calls is None else sum(
        1 for call in tool_calls if call.status is ToolCallStatus.SUCCEEDED
    )
    tool_calls_total = tool_call_count if tool_calls is None else successful_tool_calls
    return aggregate.model_copy(update={"requests": request_count, "tool_calls": tool_calls_total})


__all__ = [
    "LlmCallRecord",
    "LlmCallStatus",
    "NonEmptyString",
    "TelemetryScalar",
    "ToolCallRecord",
    "ToolCallStatus",
    "ToolFamily",
    "UsageSummary",
    "summarize_usage",
    "utc_now",
]
