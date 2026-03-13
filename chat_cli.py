from __future__ import annotations

import argparse
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from hydra import compose, initialize_config_dir
from hydra.core.global_hydra import GlobalHydra
from omegaconf import DictConfig
from pydantic_ai.models import Model
from pydantic_ai import AbstractToolset

from aftk.app import AppConfig, HYDRA_CONFIG_PATH, build_agent_from_config


@dataclass(slots=True)
class ChatCliArgs:
    config_path: str | None = None
    config_name: str = "config"
    overrides: tuple[str, ...] = ()


def parse_chat_cli_args(argv: Sequence[str] | None = None) -> ChatCliArgs:
    """Parse the lightweight chat CLI arguments."""
    parser = argparse.ArgumentParser(
        prog="aftk_chat",
        description="Launch the interactive AFTK chat UI.",
    )
    parser.add_argument(
        "-cp",
        "--config-path",
        dest="config_path",
        help="Directory containing the Hydra config file to compose.",
    )
    parser.add_argument(
        "-cn",
        "--config-name",
        dest="config_name",
        default="config",
        help="Hydra config name to compose (default: config).",
    )
    parser.add_argument(
        "overrides",
        nargs="*",
        metavar="override",
        help="Hydra override strings such as agent.model=gpt-5.4-pro.",
    )
    namespace = parser.parse_args(list(argv) if argv is not None else None)
    return ChatCliArgs(
        config_path=namespace.config_path,
        config_name=namespace.config_name,
        overrides=tuple(namespace.overrides),
    )


def resolve_chat_config_dir(config_path: str | Path | None = None) -> Path:
    """Resolve the chat config directory from an optional CLI override."""
    if config_path is None:
        return Path(HYDRA_CONFIG_PATH).resolve(strict=False)

    candidate = Path(config_path).expanduser()
    if not candidate.is_absolute():
        candidate = Path.cwd() / candidate
    return candidate.resolve(strict=False)


def load_chat_config(args: ChatCliArgs | None = None) -> DictConfig:
    """Compose the chat config manually via Hydra's compose API."""
    parsed_args = ChatCliArgs() if args is None else args
    config_dir = resolve_chat_config_dir(parsed_args.config_path)
    if not config_dir.exists():
        raise FileNotFoundError(f"Chat config path does not exist: {config_dir}")
    if not config_dir.is_dir():
        raise NotADirectoryError(f"Chat config path is not a directory: {config_dir}")

    global_hydra = GlobalHydra.instance()
    global_hydra.clear()
    try:
        with initialize_config_dir(
            config_dir=str(config_dir),
            job_name="aftk_chat",
            version_base="1.3",
        ):
            return compose(
                config_name=parsed_args.config_name,
                overrides=list(parsed_args.overrides),
            )
    finally:
        global_hydra.clear()


def chat_from_config(
    config: AppConfig | DictConfig | Mapping[str, Any] | None = None,
    *,
    base_dir: str | Path | None = None,
    model: Model | str | None = None,
    toolsets: Sequence[AbstractToolset[None]] | None = None,
) -> None:
    """Launch the interactive Pydantic AI CLI for the configured agent."""
    _, _, agent, model_settings = build_agent_from_config(
        config,
        base_dir=base_dir,
        model=model,
        toolsets=toolsets,
    )
    agent.to_cli_sync(
        prog_name="aftk_chat",
        model_settings=model_settings,
    )


def cli(argv: Sequence[str] | None = None) -> None:
    """Run the interactive chat CLI with manual Hydra config composition."""
    args = parse_chat_cli_args(argv)
    chat_from_config(
        load_chat_config(args),
        base_dir=Path.cwd(),
    )


if __name__ == "__main__":
    cli()
