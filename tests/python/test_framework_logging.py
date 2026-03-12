from __future__ import annotations

import asyncio
import json
import logging
import tempfile
import unittest
from pathlib import Path

from pydantic_ai.messages import ModelRequest, ModelResponse, TextPart, ToolCallPart
from pydantic_ai.models.function import AgentInfo, DeltaToolCall, FunctionModel
from pydantic_ai.models.test import TestModel

from aftk.cli import FrameworkCliConfig, coerce_cli_config
from aftk.config import FrameworkConfig
from aftk.logging import LoggingCliConfig, log_event, setup_logging
from aftk.runner import FrameworkRunner


class EmptyToolkitClient:
    pass


def make_config(root: Path) -> FrameworkConfig:
    root.mkdir(parents=True, exist_ok=True)
    (root / "lakefile.toml").write_text('name = "demo"\n', encoding="utf-8")
    (root / "entrypoint.md").write_text("# Demo\nFormalize the project.\n", encoding="utf-8")
    return FrameworkConfig.from_project_root(root)


class FrameworkLoggingTests(unittest.TestCase):
    def test_cli_config_coercion_supports_logging_overrides(self) -> None:
        cli_config = coerce_cli_config(
            {
                "logging": {
                    "level": "debug",
                    "console": False,
                    "live_traces": True,
                    "trace_model_events": "full",
                    "include_tool_payloads": "full",
                }
            }
        )

        self.assertIsInstance(cli_config, FrameworkCliConfig)
        self.assertEqual(cli_config.logging.level, "debug")
        self.assertFalse(cli_config.logging.console)
        self.assertTrue(cli_config.logging.live_traces)
        self.assertEqual(cli_config.logging.trace_model_events, "full")
        self.assertEqual(cli_config.logging.include_tool_payloads, "full")

    def test_setup_logging_creates_cli_and_event_logs_and_suppresses_http_info(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            runtime = setup_logging(LoggingCliConfig(console=False), config)
            try:
                log_event(
                    logging.getLogger("aftk.runner"),
                    logging.INFO,
                    "runner_start",
                    "runner started",
                    run_id="run-0001",
                )
                logging.getLogger("httpx").info("HTTP Request: POST https://example.test/v1/chat/completions")
                logging.getLogger("httpx").warning("synthetic warning")
            finally:
                runtime.close()

            cli_log = (root / ".aftk" / "cli.log").read_text(encoding="utf-8")
            self.assertIn("runner started", cli_log)
            self.assertIn("synthetic warning", cli_log)
            self.assertNotIn("HTTP Request: POST https://example.test/v1/chat/completions", cli_log)

            events_path = root / ".aftk" / "events.jsonl"
            self.assertTrue(events_path.is_file())
            events = [json.loads(line) for line in events_path.read_text(encoding="utf-8").splitlines() if line.strip()]
            self.assertEqual(events[0]["event_type"], "runner_start")
            self.assertEqual(events[0]["run_id"], "run-0001")

    def test_runner_emits_live_trace_and_lifecycle_logs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            (root / "Demo.lean").write_text("theorem demo : True := trivial\n", encoding="utf-8")

            initializer_model = TestModel(
                call_tools=[],
                custom_output_args={
                    "project_summary": "Demo project with one Lean theorem.",
                    "assumptions": [],
                    "risks": [],
                    "initial_tasks": [
                        {
                            "title": "Update Demo.lean",
                            "description": "Append a note to Demo.lean.",
                            "kind": "formalization",
                            "acceptance_criteria": ["Demo.lean contains the worker note."],
                            "scope": [{"kind": "file", "value": "Demo.lean"}],
                        }
                    ],
                },
            )

            orchestrator_calls = {"count": 0}

            def orchestrator_function(messages: list[ModelRequest | ModelResponse], info: AgentInfo) -> ModelResponse:
                del messages, info
                orchestrator_calls["count"] += 1
                if orchestrator_calls["count"] == 1:
                    payload = {
                        "project_done": False,
                        "selected_task_id": "task-0001",
                        "worker_brief": {
                            "task_id": "task-0001",
                            "title": "Update Demo.lean",
                            "description": "Append a note to Demo.lean.",
                            "acceptance_criteria": ["Demo.lean contains the worker note."],
                            "scope": [{"kind": "file", "value": "Demo.lean"}],
                            "local_context": "Add exactly one note.",
                            "suggested_starting_points": ["Use append_to_file on Demo.lean"],
                        },
                        "new_tasks": [],
                        "task_patches": [],
                        "rationale": "Run the only task.",
                    }
                else:
                    payload = {
                        "project_done": True,
                        "selected_task_id": None,
                        "worker_brief": None,
                        "new_tasks": [],
                        "task_patches": [],
                        "rationale": "The project is complete.",
                        "completion_summary": "Finished the only task.",
                    }
                return ModelResponse(parts=[TextPart(content=json.dumps(payload))])

            def worker_function(messages: list[ModelRequest | ModelResponse], info: AgentInfo) -> ModelResponse:
                del messages, info
                payload = {
                    "outcome": "completed",
                    "summary": "Added the requested note.",
                    "evidence": ["append_to_file updated Demo.lean"],
                    "changed_artifacts": [{"kind": "file", "value": "Demo.lean"}],
                    "followup_tasks": [],
                    "blockers": [],
                    "handoff_notes": "No follow-up is required.",
                }
                return ModelResponse(parts=[TextPart(content=json.dumps(payload))])

            async def worker_stream_function(messages: list[ModelRequest | ModelResponse], info: AgentInfo):
                del info
                saw_tool_return = any(
                    isinstance(message, ModelRequest)
                    and any(getattr(part, "tool_call_id", None) == "append-demo" for part in message.parts)
                    for message in messages
                )
                if not saw_tool_return:
                    yield {
                        0: DeltaToolCall(
                            name="append_to_file",
                            json_args=json.dumps({"path": "Demo.lean", "content": "\n-- logged by test\n"}),
                            tool_call_id="append-demo",
                        )
                    }
                    return

                payload = {
                    "outcome": "completed",
                    "summary": "Added the requested note.",
                    "evidence": ["append_to_file updated Demo.lean"],
                    "changed_artifacts": [{"kind": "file", "value": "Demo.lean"}],
                    "followup_tasks": [],
                    "blockers": [],
                    "handoff_notes": "No follow-up is required.",
                }
                yield json.dumps(payload)

            runtime = setup_logging(
                LoggingCliConfig(console=False, level="debug", trace_model_events="summary"),
                config,
            )
            try:
                runner = FrameworkRunner(config, logging_runtime=runtime)
                result = asyncio.run(
                    runner.run(
                        toolkit_client=EmptyToolkitClient(),  # type: ignore[arg-type]
                        initializer_model=initializer_model,
                        orchestrator_model=FunctionModel(orchestrator_function, model_name="function:orchestrator"),
                        worker_model=FunctionModel(
                            worker_function,
                            stream_function=worker_stream_function,
                            model_name="function:worker",
                        ),
                        max_iterations=4,
                    )
                )
            finally:
                runtime.close()

            self.assertTrue(result.project_done)
            cli_log = (root / ".aftk" / "cli.log").read_text(encoding="utf-8")
            self.assertIn("runner started", cli_log)
            self.assertIn("agent run started", cli_log)
            self.assertIn("tool_start append_to_file", cli_log)
            self.assertIn("tool_end append_to_file", cli_log)
            self.assertIn("model produced final result", cli_log)

            events = [
                json.loads(line)
                for line in (root / ".aftk" / "events.jsonl").read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
            event_types = {event.get("event_type") for event in events}
            self.assertIn("runner_start", event_types)
            self.assertIn("run_start", event_types)
            self.assertIn("tool_start", event_types)
            self.assertIn("tool_end", event_types)
            self.assertIn("run_end", event_types)


if __name__ == "__main__":
    unittest.main()
