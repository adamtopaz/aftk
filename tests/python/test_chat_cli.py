from __future__ import annotations

import io
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from tempfile import TemporaryDirectory

from omegaconf import OmegaConf

from chat_cli import ChatCliArgs, load_chat_config, parse_chat_cli_args


class ChatCliArgumentTests(unittest.TestCase):
    def test_parse_chat_cli_args_accepts_config_path_name_and_overrides(self) -> None:
        args = parse_chat_cli_args(
            [
                "--config-path",
                "configs",
                "--config-name",
                "chat",
                "agent.model=test-model",
                "toolkit.cwd=src",
            ]
        )

        self.assertEqual(args.config_path, "configs")
        self.assertEqual(args.config_name, "chat")
        self.assertEqual(args.overrides, ("agent.model=test-model", "toolkit.cwd=src"))

    def test_parse_chat_cli_args_rejects_unsupported_hydra_flags(self) -> None:
        with redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as ctx:
                parse_chat_cli_args(["--cfg", "job"])

        self.assertEqual(ctx.exception.code, 2)


class ChatCliConfigTests(unittest.TestCase):
    def test_load_chat_config_uses_requested_config_directory(self) -> None:
        with TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            (root / "config.yaml").write_text(
                """
agent:
  model: temp-model
  reasoning: medium
  reasoning_summary: concise
prompts:
  system_prompt: test system prompt
  user_prompt: test user prompt
toolkit:
  cwd: .
  include_search: true
trace:
  save: false
  trace_filename: trace.json
  output_filename: output.txt
""".lstrip(),
                encoding="utf-8",
            )

            cfg = load_chat_config(ChatCliArgs(config_path=tmpdir))

        self.assertEqual(OmegaConf.select(cfg, "agent.model"), "temp-model")
        self.assertEqual(OmegaConf.select(cfg, "agent.reasoning"), "medium")
        self.assertEqual(OmegaConf.select(cfg, "prompts.user_prompt"), "test user prompt")

    def test_load_chat_config_applies_hydra_overrides(self) -> None:
        with TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            (root / "config.yaml").write_text(
                """
agent:
  model: base-model
  reasoning: low
  reasoning_summary: auto
prompts:
  system_prompt: base system prompt
  user_prompt: base user prompt
toolkit:
  cwd: .
  include_search: true
trace:
  save: true
  trace_filename: agent_trace.json
  output_filename: final_output.txt
""".lstrip(),
                encoding="utf-8",
            )

            cfg = load_chat_config(
                ChatCliArgs(
                    config_path=tmpdir,
                    overrides=("agent.model=override-model", "toolkit.cwd=subdir"),
                )
            )

        self.assertEqual(OmegaConf.select(cfg, "agent.model"), "override-model")
        self.assertEqual(OmegaConf.select(cfg, "toolkit.cwd"), "subdir")


if __name__ == "__main__":
    unittest.main()
