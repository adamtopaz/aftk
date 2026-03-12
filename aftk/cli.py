from __future__ import annotations

import asyncio
import logging
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Any

import hydra
from omegaconf import DictConfig, OmegaConf

from aftk.config import AgentModelSettings, FrameworkConfig
from aftk.logging import LoggingCliConfig, log_event, setup_logging
from aftk.runner import FrameworkRunner, RunnerLoopResult
from aftk.storage import PricingTable


LOGGER = logging.getLogger("aftk.cli")


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
    logging: LoggingCliConfig = field(default_factory=LoggingCliConfig)


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

    logging_payload = payload.get("logging", {})
    if logging_payload is None:
        logging_payload = {}
    if not isinstance(logging_payload, Mapping):
        raise TypeError("logging config must be a mapping")

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
        logging=LoggingCliConfig(
            level=str(logging_payload.get("level", "info")),
            console=_coerce_bool(logging_payload.get("console", True)),
            file=_coerce_bool(logging_payload.get("file", True)),
            file_path=str(logging_payload.get("file_path", ".aftk/cli.log")),
            file_format=str(logging_payload.get("file_format", "text")),
            dependency_level=str(logging_payload.get("dependency_level", "warning")),
            include_http=_coerce_bool(logging_payload.get("include_http", False)),
            include_llm_payloads=_coerce_bool(logging_payload.get("include_llm_payloads", False)),
            include_tool_payloads=str(logging_payload.get("include_tool_payloads", "summary")),
            include_command_output=str(logging_payload.get("include_command_output", "summary")),
            live_traces=_coerce_bool(logging_payload.get("live_traces", True)),
            trace_model_events=str(logging_payload.get("trace_model_events", "summary")),
            trace_tool_events=_coerce_bool(logging_payload.get("trace_tool_events", True)),
            trace_thinking_deltas=_coerce_bool(logging_payload.get("trace_thinking_deltas", False)),
            structured_events=_coerce_bool(logging_payload.get("structured_events", True)),
            structured_event_path=str(logging_payload.get("structured_event_path", ".aftk/events.jsonl")),
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
    logging_runtime = setup_logging(cli_config.logging, framework_config)
    try:
        log_event(
            LOGGER,
            logging.INFO,
            "cli_start",
            "starting AFTK framework run",
            project_root=str(framework_config.paths.project_root),
            state_dir=framework_config.paths.relative_to_project_root(framework_config.paths.state_dir),
            max_iterations=cli_config.max_iterations,
        )
        pricing_table = load_pricing_table(cli_config)
        runner = FrameworkRunner(framework_config, pricing_table=pricing_table, logging_runtime=logging_runtime)
        result = await runner.run(max_iterations=cli_config.max_iterations)
        log_event(
            LOGGER,
            logging.INFO,
            "cli_end",
            "AFTK framework run completed",
            project_root=str(framework_config.paths.project_root),
            state_dir=framework_config.paths.relative_to_project_root(framework_config.paths.state_dir),
            summary=result.completion_summary,
        )
        return result
    except Exception:
        log_event(
            LOGGER,
            logging.ERROR,
            "cli_failed",
            "AFTK framework run failed",
            project_root=str(framework_config.paths.project_root),
            state_dir=framework_config.paths.relative_to_project_root(framework_config.paths.state_dir),
        )
        raise
    finally:
        logging_runtime.close()


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


def _coerce_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"1", "true", "yes", "on"}:
            return True
        if normalized in {"0", "false", "no", "off"}:
            return False
    return bool(value)


__all__ = [
    "AgentModelsCliConfig",
    "FrameworkCliConfig",
    "LoggingCliConfig",
    "build_framework_config",
    "coerce_cli_config",
    "load_pricing_table",
    "main",
    "render_run_result",
    "run_framework",
]
