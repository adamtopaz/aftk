from __future__ import annotations

import asyncio
import logging
from pathlib import Path

import hydra
from hydra.core.hydra_config import HydraConfig
from hydra.utils import get_original_cwd
from omegaconf import DictConfig

from aftk.app import HYDRA_CONFIG_PATH, load_app_config, run_agent_from_config

logger = logging.getLogger(__name__)


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
