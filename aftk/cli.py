from __future__ import annotations

import asyncio
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Any

import hydra
from omegaconf import DictConfig, OmegaConf

from aftk.config import AgentModelSettings, FrameworkConfig
from aftk.runner import FrameworkRunner, RunnerLoopResult
from aftk.storage import PricingTable


@dataclass(slots=True)
class AgentModelsCliConfig:
    initializer: str | None = None
    orchestrator: str | None = None
    worker: str | None = None


@dataclass(slots=True)
class FrameworkCliConfig:
    project_root: str = "."
    entrypoint_path: str = "entrypoint.md"
    sources_dir: str = "sources"
    state_dir: str = ".aftk"
    max_iterations: int = 100
    pricing_overrides_path: str | None = None
    output: str = "json"
    models: AgentModelsCliConfig = field(default_factory=AgentModelsCliConfig)


def coerce_cli_config(raw: FrameworkCliConfig | DictConfig | Mapping[str, Any]) -> FrameworkCliConfig:
    if isinstance(raw, FrameworkCliConfig):
        return raw

    payload: Mapping[str, Any]
    if isinstance(raw, DictConfig):
        resolved = OmegaConf.to_container(raw, resolve=True)
        if not isinstance(resolved, Mapping):
            raise TypeError("expected Hydra config to resolve to a mapping")
        payload = resolved
    elif isinstance(raw, Mapping):
        payload = raw
    else:
        raise TypeError(f"unsupported CLI config type: {type(raw)!r}")

    models_payload = payload.get("models", {})
    if models_payload is None:
        models_payload = {}
    if not isinstance(models_payload, Mapping):
        raise TypeError("models config must be a mapping")

    return FrameworkCliConfig(
        project_root=str(payload.get("project_root", ".")),
        entrypoint_path=str(payload.get("entrypoint_path", "entrypoint.md")),
        sources_dir=str(payload.get("sources_dir", "sources")),
        state_dir=str(payload.get("state_dir", ".aftk")),
        max_iterations=int(payload.get("max_iterations", 100)),
        pricing_overrides_path=_optional_string(payload.get("pricing_overrides_path")),
        output=str(payload.get("output", "json")),
        models=AgentModelsCliConfig(
            initializer=_optional_string(models_payload.get("initializer")),
            orchestrator=_optional_string(models_payload.get("orchestrator")),
            worker=_optional_string(models_payload.get("worker")),
        ),
    )


def build_framework_config(cli_config: FrameworkCliConfig) -> FrameworkConfig:
    return FrameworkConfig.from_project_root(
        cli_config.project_root,
        entrypoint_path=cli_config.entrypoint_path,
        sources_dir=cli_config.sources_dir,
        state_dir=cli_config.state_dir,
        models=AgentModelSettings(
            initializer=cli_config.models.initializer,
            orchestrator=cli_config.models.orchestrator,
            worker=cli_config.models.worker,
        ),
    )


def load_pricing_table(cli_config: FrameworkCliConfig) -> PricingTable | None:
    if cli_config.pricing_overrides_path is None:
        return None
    return PricingTable.from_json_file(cli_config.pricing_overrides_path)


async def run_framework(cli_config: FrameworkCliConfig) -> RunnerLoopResult:
    framework_config = build_framework_config(cli_config)
    pricing_table = load_pricing_table(cli_config)
    runner = FrameworkRunner(framework_config, pricing_table=pricing_table)
    return await runner.run(max_iterations=cli_config.max_iterations)


def render_run_result(cli_config: FrameworkCliConfig, result: RunnerLoopResult) -> str:
    output_format = cli_config.output.strip().lower()
    if output_format == "json":
        return result.model_dump_json(indent=2)
    if output_format == "text":
        return "\n".join(
            [
                "AFTK framework run complete",
                f"project_done: {result.project_done}",
                f"iterations: {result.iterations}",
                f"initialization_run_id: {result.initialization_run_id or '(none)'}",
                f"orchestrator_runs: {', '.join(result.orchestrator_run_ids) or '(none)'}",
                f"worker_runs: {', '.join(result.worker_run_ids) or '(none)'}",
                f"final_task_revision: {result.final_task_revision}",
                f"completion_summary: {result.completion_summary or '(none)'}",
            ]
        )
    raise ValueError(f"unsupported output format: {cli_config.output!r}")


@hydra.main(version_base=None, config_path="conf", config_name="main")
def main(cfg: DictConfig) -> None:
    cli_config = coerce_cli_config(cfg)
    result = asyncio.run(run_framework(cli_config))
    print(render_run_result(cli_config, result))


def _optional_string(value: object) -> str | None:
    if value is None:
        return None
    rendered = str(value).strip()
    return rendered or None


__all__ = [
    "AgentModelsCliConfig",
    "FrameworkCliConfig",
    "build_framework_config",
    "coerce_cli_config",
    "load_pricing_table",
    "main",
    "render_run_result",
    "run_framework",
]
