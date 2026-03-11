from __future__ import annotations

import json
from fnmatch import fnmatch
from pathlib import Path

from pydantic import Field, model_validator

from aftk.config import FrameworkModel
from aftk.storage.telemetry import NonEmptyString, UsageSummary


class ModelPricingRule(FrameworkModel):
    model_pattern: NonEmptyString
    input_cost_per_million_tokens: float = Field(default=0.0, ge=0)
    cache_write_cost_per_million_tokens: float = Field(default=0.0, ge=0)
    cache_read_cost_per_million_tokens: float = Field(default=0.0, ge=0)
    output_cost_per_million_tokens: float = Field(default=0.0, ge=0)
    input_audio_cost_per_million_tokens: float = Field(default=0.0, ge=0)
    cache_audio_read_cost_per_million_tokens: float = Field(default=0.0, ge=0)
    output_audio_cost_per_million_tokens: float = Field(default=0.0, ge=0)


class PricingTable(FrameworkModel):
    currency: NonEmptyString = "USD"
    source: str | None = None
    rules: list[ModelPricingRule] = Field(default_factory=list)

    @classmethod
    def from_json_file(cls, path: str | Path) -> PricingTable:
        payload = json.loads(Path(path).read_text(encoding="utf-8"))
        table = cls.model_validate(payload)
        return table.model_copy(update={"source": str(Path(path).expanduser().resolve(strict=False))})

    def merge(self, override: PricingTable | None) -> PricingTable:
        if override is None:
            return self
        currency = override.currency or self.currency
        return PricingTable(
            currency=currency,
            source=override.source or self.source,
            rules=[*override.rules, *self.rules],
        )

    def with_override_file(self, path: str | Path | None) -> PricingTable:
        if path is None:
            return self
        return self.merge(self.from_json_file(path))

    def resolve(self, model_name: str | None) -> ModelPricingRule | None:
        if not model_name:
            return None
        for rule in self.rules:
            if rule.model_pattern == model_name:
                return rule
        for rule in self.rules:
            if fnmatch(model_name, rule.model_pattern):
                return rule
        return None


class CostSummary(FrameworkModel):
    currency: NonEmptyString = "USD"
    model_name: str | None = None
    pricing_source: str | None = None
    pricing_found: bool = False
    input_cost: float = Field(default=0.0, ge=0)
    cache_write_cost: float = Field(default=0.0, ge=0)
    cache_read_cost: float = Field(default=0.0, ge=0)
    output_cost: float = Field(default=0.0, ge=0)
    input_audio_cost: float = Field(default=0.0, ge=0)
    cache_audio_read_cost: float = Field(default=0.0, ge=0)
    output_audio_cost: float = Field(default=0.0, ge=0)
    other_cost: float = Field(default=0.0, ge=0)
    total_cost: float = Field(default=0.0, ge=0)

    @model_validator(mode="after")
    def validate_total_cost(self) -> CostSummary:
        calculated_total = (
            self.input_cost
            + self.cache_write_cost
            + self.cache_read_cost
            + self.output_cost
            + self.input_audio_cost
            + self.cache_audio_read_cost
            + self.output_audio_cost
            + self.other_cost
        )
        if abs(self.total_cost - calculated_total) > 1e-12:
            raise ValueError("total_cost must equal the sum of the individual cost components")
        return self

    def add(self, other: CostSummary | None) -> CostSummary:
        if other is None:
            return self
        if self.currency != other.currency:
            raise ValueError(f"cannot add costs with different currencies: {self.currency} vs {other.currency}")
        return CostSummary(
            currency=self.currency,
            model_name=None,
            pricing_source=self.pricing_source if self.pricing_source == other.pricing_source else None,
            pricing_found=self.pricing_found or other.pricing_found,
            input_cost=self.input_cost + other.input_cost,
            cache_write_cost=self.cache_write_cost + other.cache_write_cost,
            cache_read_cost=self.cache_read_cost + other.cache_read_cost,
            output_cost=self.output_cost + other.output_cost,
            input_audio_cost=self.input_audio_cost + other.input_audio_cost,
            cache_audio_read_cost=self.cache_audio_read_cost + other.cache_audio_read_cost,
            output_audio_cost=self.output_audio_cost + other.output_audio_cost,
            other_cost=self.other_cost + other.other_cost,
            total_cost=self.total_cost + other.total_cost,
        )


def estimate_usage_cost(
    usage: UsageSummary | object | None,
    *,
    model_name: str | None,
    pricing_table: PricingTable | None,
) -> CostSummary:
    usage_summary = UsageSummary.from_value(usage)
    if pricing_table is None:
        return CostSummary(currency="USD", model_name=model_name, pricing_found=False, total_cost=0.0)

    rule = pricing_table.resolve(model_name)
    if rule is None:
        return CostSummary(
            currency=pricing_table.currency,
            model_name=model_name,
            pricing_source=pricing_table.source,
            pricing_found=False,
            total_cost=0.0,
        )

    input_cost = _token_cost(usage_summary.input_tokens, rule.input_cost_per_million_tokens)
    cache_write_cost = _token_cost(usage_summary.cache_write_tokens, rule.cache_write_cost_per_million_tokens)
    cache_read_cost = _token_cost(usage_summary.cache_read_tokens, rule.cache_read_cost_per_million_tokens)
    output_cost = _token_cost(usage_summary.output_tokens, rule.output_cost_per_million_tokens)
    input_audio_cost = _token_cost(usage_summary.input_audio_tokens, rule.input_audio_cost_per_million_tokens)
    cache_audio_read_cost = _token_cost(
        usage_summary.cache_audio_read_tokens,
        rule.cache_audio_read_cost_per_million_tokens,
    )
    output_audio_cost = _token_cost(usage_summary.output_audio_tokens, rule.output_audio_cost_per_million_tokens)
    total_cost = (
        input_cost
        + cache_write_cost
        + cache_read_cost
        + output_cost
        + input_audio_cost
        + cache_audio_read_cost
        + output_audio_cost
    )
    return CostSummary(
        currency=pricing_table.currency,
        model_name=model_name,
        pricing_source=pricing_table.source,
        pricing_found=True,
        input_cost=input_cost,
        cache_write_cost=cache_write_cost,
        cache_read_cost=cache_read_cost,
        output_cost=output_cost,
        input_audio_cost=input_audio_cost,
        cache_audio_read_cost=cache_audio_read_cost,
        output_audio_cost=output_audio_cost,
        total_cost=total_cost,
    )


def sum_costs(costs: list[CostSummary], *, currency: str = "USD") -> CostSummary:
    total = CostSummary(currency=currency, total_cost=0.0)
    for cost in costs:
        total = total.add(cost)
    return total


def _token_cost(tokens: int, rate_per_million_tokens: float) -> float:
    if tokens <= 0 or rate_per_million_tokens <= 0:
        return 0.0
    return (tokens / 1_000_000) * rate_per_million_tokens


__all__ = [
    "CostSummary",
    "ModelPricingRule",
    "PricingTable",
    "estimate_usage_cost",
    "sum_costs",
]
