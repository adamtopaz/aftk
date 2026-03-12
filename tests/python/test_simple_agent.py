from __future__ import annotations

import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import cast

from omegaconf import DictConfig, OmegaConf
from pydantic_ai.models.test import TestModel

from main import (
    DEFAULT_MODEL_NAME,
    AgentConfig,
    AppConfig,
    PromptConfig,
    ToolkitConfig,
    TraceConfig,
    build_agent,
    build_model,
    build_model_settings,
    load_app_config,
    main,
    run_agent_from_config,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
CONFIG_PATH = REPO_ROOT / "config.yaml"


class SimpleAgentConfigTests(unittest.TestCase):
    def test_build_model_uses_openai_responses_route(self) -> None:
        self.assertEqual(build_model(), f"openai-responses:{DEFAULT_MODEL_NAME}")
        self.assertEqual(build_model(" custom-model "), "openai-responses:custom-model")

    def test_build_model_settings_uses_requested_reasoning_effort(self) -> None:
        settings = build_model_settings("xhigh")

        self.assertEqual(settings.get("openai_reasoning_effort"), "xhigh")
        self.assertEqual(settings.get("openai_reasoning_summary"), "auto")

    def test_build_model_settings_rejects_invalid_thinking_level(self) -> None:
        with self.assertRaises(ValueError):
            build_model_settings("extreme")  # type: ignore[arg-type]

    def test_load_app_config_from_hydra_yaml(self) -> None:
        config = load_app_config(cast(DictConfig, OmegaConf.load(CONFIG_PATH)))

        self.assertEqual(config.agent.model, DEFAULT_MODEL_NAME)
        self.assertEqual(config.agent.reasoning, "xhigh")
        self.assertIn("coding agent", config.prompts.system_prompt)
        self.assertIn("Say hello", config.prompts.user_prompt)
        self.assertEqual(config.toolkit.cwd, ".")
        self.assertTrue(config.trace.save)


class SimpleAgentRunTests(unittest.IsolatedAsyncioTestCase):
    async def test_build_agent_exposes_coding_tools(self) -> None:
        with TemporaryDirectory() as tmpdir:
            agent = build_agent(cwd=tmpdir)
            self.assertEqual(agent.model, f"openai-responses:{DEFAULT_MODEL_NAME}")

            model = TestModel(call_tools=[], custom_output_text="ok")
            result = await agent.run("hello", model=model, model_settings=build_model_settings())

            self.assertEqual(result.output, "ok")
            assert model.last_model_request_parameters is not None
            tool_names = {tool.name for tool in model.last_model_request_parameters.function_tools}
            self.assertEqual(tool_names, {"read", "write", "edit", "bash", "grep", "find", "ls"})

    async def test_main_runs_one_turn_and_returns_plain_text(self) -> None:
        with TemporaryDirectory() as tmpdir:
            model = TestModel(call_tools=[], custom_output_text="final response")

            output = await main(
                AppConfig(
                    agent=AgentConfig(reasoning="low"),
                    prompts=PromptConfig(
                        system_prompt="Use tools when useful.",
                        user_prompt="Inspect the repository.",
                    ),
                    toolkit=ToolkitConfig(cwd=tmpdir),
                ),
                model=model,
            )

            self.assertEqual(output, "final response")
            assert model.last_model_request_parameters is not None
            tool_names = {tool.name for tool in model.last_model_request_parameters.function_tools}
            self.assertIn("read", tool_names)
            self.assertIn("bash", tool_names)

    async def test_run_agent_from_config_writes_trace_into_output_dir(self) -> None:
        with TemporaryDirectory() as tmpdir, TemporaryDirectory() as outdir:
            config = AppConfig(
                agent=AgentConfig(reasoning="xhigh"),
                prompts=PromptConfig(
                    system_prompt="Use tools when useful.",
                    user_prompt="Inspect the repository.",
                ),
                toolkit=ToolkitConfig(cwd="."),
                trace=TraceConfig(save=True, trace_filename="trace.json", output_filename="output.txt"),
            )
            model = TestModel(call_tools=[], custom_output_text="saved response")

            artifacts = await run_agent_from_config(
                config,
                base_dir=tmpdir,
                output_dir=outdir,
                model=model,
            )

            self.assertEqual(artifacts.output, "saved response")
            trace_path = Path(outdir) / "trace.json"
            output_path = Path(outdir) / "output.txt"
            self.assertTrue(trace_path.exists())
            self.assertTrue(output_path.exists())
            self.assertEqual(output_path.read_text(encoding="utf-8"), "saved response")

            payload = json.loads(trace_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["output"], "saved response")
            self.assertEqual(payload["config"]["agent"]["reasoning"], "xhigh")
            self.assertTrue(payload["node_trace"])
            self.assertTrue(payload["messages"])
            self.assertEqual(payload["toolkit_cwd"], str(Path(tmpdir).resolve()))


if __name__ == "__main__":
    unittest.main()
