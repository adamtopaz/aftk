from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from aftk.runner import RunnerLoopResult
from main import FrameworkCliConfig, build_framework_config, coerce_cli_config, render_run_result


REPO_ROOT = Path(__file__).resolve().parents[2]


def make_project(root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    (root / "lakefile.toml").write_text('name = "demo"\n', encoding="utf-8")
    (root / "entrypoint.md").write_text("# Demo\nFormalize the project.\n", encoding="utf-8")


class FrameworkMainTests(unittest.TestCase):
    def test_cli_config_coercion_and_framework_config_use_aftk_state_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            make_project(root)

            cli_config = coerce_cli_config(
                {
                    "project_root": str(root),
                    "max_iterations": 12,
                    "models": {
                        "initializer": "openai:gpt-5-mini",
                        "orchestrator": "openai:gpt-5",
                        "worker": "openai:gpt-5-mini",
                    },
                }
            )
            framework_config = build_framework_config(cli_config)

            self.assertIsInstance(cli_config, FrameworkCliConfig)
            self.assertEqual(cli_config.state_dir, ".aftk")
            self.assertEqual(cli_config.max_iterations, 12)
            self.assertEqual(framework_config.paths.state_dir, (root / ".aftk").resolve())
            self.assertEqual(framework_config.paths.project_state_dir, (root / ".aftk" / "project").resolve())
            self.assertEqual(framework_config.models.orchestrator, "openai:gpt-5")

    def test_render_run_result_supports_json_and_text(self) -> None:
        result = RunnerLoopResult(
            project_done=True,
            completion_summary="Done.",
            iterations=3,
            initialization_run_id="run-0001",
            orchestrator_run_ids=["run-0002", "run-0004"],
            worker_run_ids=["run-0003"],
            final_task_revision=5,
        )

        json_output = render_run_result(FrameworkCliConfig(output="json"), result)
        text_output = render_run_result(FrameworkCliConfig(output="text"), result)

        self.assertTrue(json.loads(json_output)["project_done"])
        self.assertIn("AFTK framework run complete", text_output)
        self.assertIn("worker_runs: run-0003", text_output)

    def test_lake_run_autoformalize_help_smoke(self) -> None:
        completed = subprocess.run(
            ["lake", "run", "autoformalize", "--help"],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )

        self.assertIn("cli is powered by Hydra.", completed.stdout)
        self.assertIn("state_dir: .aftk", completed.stdout)


if __name__ == "__main__":
    unittest.main()
