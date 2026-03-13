from __future__ import annotations

import asyncio
import dataclasses
import json
import logging
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Literal

import hydra
from hydra.core.hydra_config import HydraConfig
from hydra.utils import get_original_cwd
from omegaconf import DictConfig, OmegaConf
from pydantic_ai import AbstractToolset, Agent
from pydantic_ai.models import Model
from pydantic_ai.models.openai import OpenAIResponsesModelSettings

from aftk import AsyncAftkClient, ProjectRootNotFoundError, detect_project_root
from aftk.toolkits.aftk import AftkToolkit
from aftk.toolkits.coding import CodingToolkit

logger = logging.getLogger(__name__)

ThinkingLevel = Literal["low", "medium", "high", "xhigh"]
ReasoningSummary = Literal["auto", "concise", "detailed"]

DEFAULT_MODEL_NAME = "gpt-5.4-pro"
DEFAULT_THINKING_LEVEL: ThinkingLevel = "xhigh"
DEFAULT_REASONING_SUMMARY: ReasoningSummary = "auto"
SYSTEM_PROMPT = """You are a coding agent working in the current repository.
Use the available coding and AFTK tools when they help, and return a plain-text final answer.
"""
USER_PROMPT = "Say hello!"
DEFAULT_TRACE_FILENAME = "agent_trace.json"
DEFAULT_OUTPUT_FILENAME = "final_output.txt"
HYDRA_CONFIG_PATH = str(Path(__file__).resolve().parent)

_ALLOWED_THINKING_LEVELS: tuple[ThinkingLevel, ...] = ("low", "medium", "high", "xhigh")
_ALLOWED_REASONING_SUMMARIES: tuple[ReasoningSummary, ...] = ("auto", "concise", "detailed")


@dataclass(slots=True)
class AgentConfig:
    model: str = DEFAULT_MODEL_NAME
    reasoning: ThinkingLevel = DEFAULT_THINKING_LEVEL
    reasoning_summary: ReasoningSummary = DEFAULT_REASONING_SUMMARY


@dataclass(slots=True)
class PromptConfig:
    system_prompt: str = SYSTEM_PROMPT
    user_prompt: str = USER_PROMPT


@dataclass(slots=True)
class ToolkitConfig:
    cwd: str | None = "."
    include_search: bool = True


@dataclass(slots=True)
class TraceConfig:
    save: bool = True
    trace_filename: str = DEFAULT_TRACE_FILENAME
    output_filename: str = DEFAULT_OUTPUT_FILENAME


@dataclass(slots=True)
class AppConfig:
    agent: AgentConfig = field(default_factory=AgentConfig)
    prompts: PromptConfig = field(default_factory=PromptConfig)
    toolkit: ToolkitConfig = field(default_factory=ToolkitConfig)
    trace: TraceConfig = field(default_factory=TraceConfig)


@dataclass(slots=True)
class RunArtifacts:
    output: str
    run_id: str
    usage: dict[str, Any]
    model_reference: str
    toolkit_cwd: str
    node_trace: list[dict[str, Any]]
    messages: list[Any]
    config: dict[str, Any]


def _normalize_section(raw: Mapping[str, Any], key: str) -> dict[str, Any]:
    value = raw.get(key, {})
    if not isinstance(value, Mapping):
        raise TypeError(f"Config section {key!r} must be a mapping.")
    return dict(value)


def _config_section(config: DictConfig, key: str) -> dict[str, Any]:
    section = OmegaConf.select(config, key)
    if section is None:
        return {}

    container = OmegaConf.to_container(section, resolve=True)
    if not isinstance(container, Mapping):
        raise TypeError(f"Config section {key!r} must resolve to a mapping.")
    return dict(container)


def load_app_config(config: AppConfig | DictConfig | Mapping[str, Any] | None = None) -> AppConfig:
    """Load the application configuration from Hydra/OmegaConf data."""
    if config is None:
        return AppConfig()
    if isinstance(config, AppConfig):
        return config

    if isinstance(config, DictConfig):
        return AppConfig(
            agent=AgentConfig(**_config_section(config, "agent")),
            prompts=PromptConfig(**_config_section(config, "prompts")),
            toolkit=ToolkitConfig(**_config_section(config, "toolkit")),
            trace=TraceConfig(**_config_section(config, "trace")),
        )

    raw = config
    return AppConfig(
        agent=AgentConfig(**_normalize_section(raw, "agent")),
        prompts=PromptConfig(**_normalize_section(raw, "prompts")),
        toolkit=ToolkitConfig(**_normalize_section(raw, "toolkit")),
        trace=TraceConfig(**_normalize_section(raw, "trace")),
    )


def build_model(model_name: str = DEFAULT_MODEL_NAME) -> str:
    """Build the default OpenAI Responses model reference."""
    cleaned = model_name.strip()
    if not cleaned:
        raise ValueError("Model name must not be empty.")
    return f"openai-responses:{cleaned}"


def build_model_settings(
    thinking_level: ThinkingLevel = DEFAULT_THINKING_LEVEL,
    reasoning_summary: ReasoningSummary = DEFAULT_REASONING_SUMMARY,
) -> OpenAIResponsesModelSettings:
    """Build model settings for a one-turn OpenAI Responses run."""
    if thinking_level not in _ALLOWED_THINKING_LEVELS:
        expected = ", ".join(_ALLOWED_THINKING_LEVELS)
        raise ValueError(f"Unsupported thinking level {thinking_level!r}. Expected one of: {expected}.")
    if reasoning_summary not in _ALLOWED_REASONING_SUMMARIES:
        expected = ", ".join(_ALLOWED_REASONING_SUMMARIES)
        raise ValueError(f"Unsupported reasoning summary {reasoning_summary!r}. Expected one of: {expected}.")

    return OpenAIResponsesModelSettings(
        openai_reasoning_effort=thinking_level,
        openai_reasoning_summary=reasoning_summary,
    )


def resolve_toolkit_cwd(cwd: str | Path | None, *, base_dir: str | Path | None = None) -> Path:
    """Resolve the configured toolkit working directory against a stable base directory."""
    resolved_base = Path.cwd() if base_dir is None else Path(base_dir).expanduser().resolve(strict=False)
    if cwd is None or str(cwd).strip() == "":
        return resolved_base

    candidate = Path(cwd).expanduser()
    if not candidate.is_absolute():
        candidate = resolved_base / candidate
    return candidate.resolve(strict=False)


def resolve_aftk_project_root(toolkit_cwd: str | Path, *, base_dir: str | Path | None = None) -> Path | None:
    """Resolve the Lake project root that should back the AFTK toolkit, if available."""
    candidates: list[Path] = []
    if base_dir is not None:
        candidates.append(Path(base_dir).expanduser().resolve(strict=False))

    resolved_toolkit_cwd = Path(toolkit_cwd).expanduser().resolve(strict=False)
    if resolved_toolkit_cwd not in candidates:
        candidates.append(resolved_toolkit_cwd)

    for candidate in candidates:
        try:
            return detect_project_root(candidate)
        except ProjectRootNotFoundError:
            continue

    return None


def build_agent(
    *,
    model_name: str = DEFAULT_MODEL_NAME,
    system_prompt: str = SYSTEM_PROMPT,
    cwd: str | Path | None = None,
    base_dir: str | Path | None = None,
    include_search: bool = True,
    model: Model | str | None = None,
    toolsets: Sequence[AbstractToolset[None]] | None = None,
) -> Agent[None, str]:
    """Construct the simple agent with the local coding and AFTK toolkits attached.

    The default model is returned as a routed model string so importing this module does not require
    OpenAI credentials. Pydantic AI resolves that model reference when the agent actually runs.
    """
    resolved_model = model if model is not None else build_model(model_name)

    if toolsets is None:
        resolved_cwd = resolve_toolkit_cwd(cwd, base_dir=base_dir)
        resolved_toolsets: list[AbstractToolset[None]] = [
            CodingToolkit(
                cwd=resolved_cwd,
                include_search=include_search,
            )
        ]

        aftk_project_root = resolve_aftk_project_root(resolved_cwd, base_dir=base_dir)
        if aftk_project_root is not None:
            resolved_toolsets.append(
                AftkToolkit(
                    AsyncAftkClient(project_root=aftk_project_root),
                    close_client_on_exit=True,
                )
            )
    else:
        resolved_toolsets = list(toolsets)

    return Agent(
        resolved_model,
        output_type=str,
        instructions=system_prompt,
        toolsets=resolved_toolsets,
        defer_model_check=isinstance(resolved_model, str),
    )


async def run_agent_from_config(
    config: AppConfig | DictConfig | Mapping[str, Any],
    *,
    base_dir: str | Path | None = None,
    output_dir: str | Path | None = None,
    model: Model | str | None = None,
    toolsets: Sequence[AbstractToolset[None]] | None = None,
) -> RunArtifacts:
    """Run one full agent turn from an application configuration and collect trace data."""
    resolved_config = load_app_config(config)
    toolkit_cwd = resolve_toolkit_cwd(resolved_config.toolkit.cwd, base_dir=base_dir)
    agent = build_agent(
        model_name=resolved_config.agent.model,
        system_prompt=resolved_config.prompts.system_prompt,
        cwd=toolkit_cwd,
        base_dir=base_dir,
        include_search=resolved_config.toolkit.include_search,
        model=model,
        toolsets=toolsets,
    )

    node_trace: list[dict[str, Any]] = []
    async with agent.iter(
        resolved_config.prompts.user_prompt,
        model_settings=build_model_settings(
            resolved_config.agent.reasoning,
            resolved_config.agent.reasoning_summary,
        ),
    ) as agent_run:
        async for node in agent_run:
            node_trace.append(
                {
                    "index": len(node_trace),
                    "kind": type(node).__name__,
                    "repr": repr(node),
                }
            )

    result = agent_run.result
    if result is None:
        raise RuntimeError("Agent run finished without a result.")

    artifacts = RunArtifacts(
        output=result.output,
        run_id=result.run_id,
        usage=dataclasses.asdict(result.usage()),
        model_reference=build_model(resolved_config.agent.model),
        toolkit_cwd=str(toolkit_cwd),
        node_trace=node_trace,
        messages=json.loads(result.all_messages_json().decode("utf-8")),
        config=dataclasses.asdict(resolved_config),
    )

    if output_dir is not None and resolved_config.trace.save:
        save_run_artifacts(artifacts, Path(output_dir), resolved_config.trace)

    return artifacts


def save_run_artifacts(artifacts: RunArtifacts, output_dir: Path, trace_config: TraceConfig) -> None:
    """Save the final output and full run trace into Hydra's output directory."""
    output_dir.mkdir(parents=True, exist_ok=True)

    trace_path = output_dir / trace_config.trace_filename
    trace_payload = {
        "config": artifacts.config,
        "model_reference": artifacts.model_reference,
        "toolkit_cwd": artifacts.toolkit_cwd,
        "run_id": artifacts.run_id,
        "usage": artifacts.usage,
        "output": artifacts.output,
        "node_trace": artifacts.node_trace,
        "messages": artifacts.messages,
    }
    trace_path.write_text(json.dumps(trace_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    output_path = output_dir / trace_config.output_filename
    output_path.write_text(artifacts.output, encoding="utf-8")

    logger.info("Saved agent trace to %s", trace_path)
    logger.info("Saved final output to %s", output_path)


async def main(
    config: AppConfig | DictConfig | Mapping[str, Any] | None = None,
    *,
    base_dir: str | Path | None = None,
    output_dir: str | Path | None = None,
    model: Model | str | None = None,
    toolsets: Sequence[AbstractToolset[None]] | None = None,
) -> str:
    """Run one full agent turn and return the final plain-text response."""
    artifacts = await run_agent_from_config(
        AppConfig() if config is None else config,
        base_dir=base_dir,
        output_dir=output_dir,
        model=model,
        toolsets=toolsets,
    )
    return artifacts.output

@hydra.main(version_base="1.3", config_path=HYDRA_CONFIG_PATH, config_name="config")
def _hydra_cli(cfg: DictConfig) -> None:
    """Hydra entrypoint for configuring and running the local agent."""
    app_config = load_app_config(cfg)
    hydra_output_dir = Path(HydraConfig.get().runtime.output_dir)
    original_cwd = Path(get_original_cwd())

    logger.info("Hydra output directory: %s", hydra_output_dir)
    logger.info("Original working directory: %s", original_cwd)

    artifacts = asyncio.run(
        run_agent_from_config(
            app_config,
            base_dir=original_cwd,
            output_dir=hydra_output_dir,
        )
    )
    print(artifacts.output)


def cli() -> None:
    """Run the Hydra CLI using the repository's `config.yaml`."""
    _hydra_cli()


if __name__ == "__main__":
    cli()
