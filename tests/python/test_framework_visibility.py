from __future__ import annotations

import asyncio
import json
import shutil
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path

from pydantic_ai.messages import ModelRequest, ModelResponse, TextPart, ToolCallPart, ToolReturnPart
from pydantic_ai.models.function import AgentInfo, FunctionModel
from pydantic_ai.models.test import TestModel

from aftk.config import FrameworkConfig
from aftk.inspection import FrameworkInspectionService
from aftk.inspection_cli import main as inspection_main
from aftk.runner import FrameworkRunner
from aftk.storage import RunLogStore, ToolFamily
from aftk.tasks import TaskStatus


REPO_ROOT = Path(__file__).resolve().parents[2]
FRAMEWORK_FIXTURE_ROOT = REPO_ROOT / "tests" / "framework" / "fixtures" / "basic_project"


class EmptyToolkitClient:
    pass


def copy_fixture_project(target_root: Path) -> Path:
    project_root = target_root / "project"
    shutil.copytree(FRAMEWORK_FIXTURE_ROOT, project_root)
    return project_root


class FrameworkInspectionServiceTests(unittest.TestCase):
    def test_inspection_does_not_create_framework_state_for_uninitialized_project(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = copy_fixture_project(Path(tmp))
            config = FrameworkConfig.from_project_root(root)
            inspector = FrameworkInspectionService(config)

            report = inspector.build_report()

            self.assertIsNone(report.snapshot)
            self.assertIsNone(report.initialization)
            self.assertIsNone(report.task_state)
            self.assertEqual(report.recent_runs, [])
            self.assertIsNone(report.rollups)
            self.assertFalse((root / ".aftk").exists())
            self.assertIn("Snapshot: missing", inspector.render_text_report(report))

    def test_inspection_cli_reports_uninitialized_project_without_creating_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = copy_fixture_project(Path(tmp))
            stdout = StringIO()
            stderr = StringIO()

            with redirect_stdout(stdout), redirect_stderr(stderr):
                exit_code = inspection_main([str(root)])

            self.assertEqual(exit_code, 0)
            self.assertEqual(stderr.getvalue(), "")
            self.assertIn("AFTK framework inspection", stdout.getvalue())
            self.assertIn("Snapshot: missing", stdout.getvalue())
            self.assertFalse((root / ".aftk").exists())


class FixtureProjectRunnerTests(unittest.TestCase):
    def test_fixture_project_runs_end_to_end_with_build_and_visibility_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = copy_fixture_project(Path(tmp))
            config = FrameworkConfig.from_project_root(root)
            runner = FrameworkRunner(config)

            initializer_model = TestModel(
                call_tools=[],
                custom_output_args={
                    "project_summary": "Demo fixture project with a single greeting update task.",
                    "assumptions": ["The fixture project builds before edits."],
                    "risks": ["A malformed edit could break the build."],
                    "initial_tasks": [
                        {
                            "title": "Tune demo greeting",
                            "description": "Change the greeting string in Demo/Basic.lean and validate with lake build.",
                            "kind": "formalization",
                            "acceptance_criteria": ["Demo/Basic.lean uses the new greeting.", "lake build succeeds."],
                            "scope": [{"kind": "file", "value": "Demo/Basic.lean"}],
                            "context_summary": "Keep the edit local to Demo/Basic.lean.",
                        }
                    ],
                },
            )

            orchestrator_calls = {"count": 0}

            def orchestrator_function(messages: list[ModelRequest | ModelResponse], info: AgentInfo) -> ModelResponse:
                orchestrator_calls["count"] += 1
                if orchestrator_calls["count"] == 1:
                    payload = {
                        "project_done": False,
                        "selected_task_id": "task-0001",
                        "worker_brief": {
                            "task_id": "task-0001",
                            "title": "Tune demo greeting",
                            "description": "Change the greeting string in Demo/Basic.lean and validate with lake build.",
                            "acceptance_criteria": ["Demo/Basic.lean uses the new greeting.", "lake build succeeds."],
                            "scope": [{"kind": "file", "value": "Demo/Basic.lean"}],
                            "local_context": "Search for the existing hello string, replace it, then run lake build.",
                            "suggested_starting_points": ["Search for the current hello definition", "Validate with lake build"],
                        },
                        "new_tasks": [],
                        "task_patches": [],
                        "rationale": "The fixture task is ready and should be executed now.",
                    }
                else:
                    payload = {
                        "project_done": True,
                        "selected_task_id": None,
                        "worker_brief": None,
                        "new_tasks": [],
                        "task_patches": [
                            {
                                "task_id": "task-0001",
                                "new_status": "completed",
                                "append_notes": ["Worker replaced the greeting and validated the build."],
                            }
                        ],
                        "rationale": "The only planned fixture task completed successfully.",
                        "completion_summary": "The fixture project greeting was updated and the build stayed green.",
                    }
                return ModelResponse(parts=[TextPart(content=json.dumps(payload))])

            def worker_function(messages: list[ModelRequest | ModelResponse], info: AgentInfo) -> ModelResponse:
                seen_returns = {
                    part.tool_name
                    for message in messages
                    if isinstance(message, ModelRequest)
                    for part in message.parts
                    if isinstance(part, ToolReturnPart)
                }
                if "search_project_text" not in seen_returns:
                    return ModelResponse(
                        parts=[
                            ToolCallPart(
                                tool_name="search_project_text",
                                args={"query": 'def hello : String := "world"', "limit": 5},
                                tool_call_id="search-hello",
                            )
                        ]
                    )
                if "replace_in_file" not in seen_returns:
                    return ModelResponse(
                        parts=[
                            ToolCallPart(
                                tool_name="replace_in_file",
                                args={
                                    "path": "Demo/Basic.lean",
                                    "old_text": 'def hello : String := "world"',
                                    "new_text": 'def hello : String := "framework"',
                                },
                                tool_call_id="replace-hello",
                            )
                        ]
                    )
                if "lake_build" not in seen_returns:
                    return ModelResponse(
                        parts=[
                            ToolCallPart(
                                tool_name="lake_build",
                                args={"timeout_seconds": 120.0},
                                tool_call_id="build-fixture",
                            )
                        ]
                    )
                payload = {
                    "outcome": "completed",
                    "summary": "Updated the greeting string and validated the fixture project with lake build.",
                    "evidence": [
                        'search_project_text located `def hello : String := "world"`',
                        'replace_in_file updated Demo/Basic.lean',
                        "lake_build completed successfully",
                    ],
                    "changed_artifacts": [{"kind": "file", "value": "Demo/Basic.lean"}],
                    "followup_tasks": [],
                    "blockers": [],
                    "handoff_notes": "The local edit is complete and the project still builds.",
                }
                return ModelResponse(parts=[TextPart(content=json.dumps(payload))])

            result = asyncio.run(
                runner.run(
                    toolkit_client=EmptyToolkitClient(),  # type: ignore[arg-type]
                    initializer_model=initializer_model,
                    orchestrator_model=FunctionModel(orchestrator_function, model_name="function:fixture-orchestrator"),
                    worker_model=FunctionModel(worker_function, model_name="function:fixture-worker"),
                    max_iterations=4,
                )
            )

            self.assertTrue(result.project_done)
            self.assertEqual(
                result.completion_summary,
                "The fixture project greeting was updated and the build stayed green.",
            )
            self.assertEqual(result.worker_run_ids, ["run-0003"])

            state = runner.task_service.load_state()
            self.assertEqual(state.tasks["task-0001"].status, TaskStatus.COMPLETED)
            self.assertIn('def hello : String := "framework"', (root / "Demo" / "Basic.lean").read_text(encoding="utf-8"))

            worker_store = RunLogStore(config, "run-0003")
            tool_calls = worker_store.load_tool_calls()
            self.assertEqual([call.tool_name for call in tool_calls], ["search_project_text", "replace_in_file", "lake_build"])
            self.assertTrue(all(call.tool_family is ToolFamily.CODING for call in tool_calls))
            self.assertTrue(worker_store.coding_actions_path.is_file())
            coding_actions_text = worker_store.coding_actions_path.read_text(encoding="utf-8")
            self.assertIn("search_project_text", coding_actions_text)
            self.assertIn("replace_in_file", coding_actions_text)
            self.assertIn("lake_build", coding_actions_text)

            rollups = runner.run_collection.load_rollups()
            self.assertEqual(rollups.project.tool_call_count, 4)
            self.assertEqual(rollups.by_attempt["attempt-0001"].tool_call_count, 3)
            self.assertEqual(rollups.by_agent_role["worker"].tool_call_count, 3)
            self.assertEqual(rollups.by_agent_role["initializer"].tool_call_count, 1)

            inspector = FrameworkInspectionService(config)
            report = inspector.build_report()
            self.assertIsNotNone(report.snapshot)
            self.assertIsNotNone(report.initialization)
            self.assertIsNotNone(report.task_state)
            self.assertIsNotNone(report.rollups)
            assert report.task_counts is not None
            self.assertEqual(report.task_counts.completed, 1)
            self.assertEqual(report.ready_task_ids, [])
            self.assertEqual(report.in_progress_task_ids, [])
            assert report.event_counts is not None
            self.assertGreaterEqual(report.event_counts.total, 5)
            event_kinds = {event.kind.value for event in report.recent_events}
            self.assertIn("task_created", event_kinds)
            self.assertIn("attempt_finished", event_kinds)
            self.assertIn("task_patched", event_kinds)
            self.assertEqual([run.record.run_id for run in report.recent_runs], ["run-0004", "run-0003", "run-0002", "run-0001"])
            self.assertEqual(report.recent_runs[1].tool_call_count, 3)
            self.assertEqual(report.recent_runs[1].coding_action_count, 3)

            text_report = inspector.render_text_report(report)
            self.assertIn("AFTK framework inspection", text_report)
            self.assertIn("Tune demo greeting", text_report)
            self.assertIn("Recent task events:", text_report)
            self.assertIn("attempt_finished", text_report)
            self.assertIn("project usage: requests=", text_report)
            self.assertIn("by attempt:", text_report)
            self.assertIn("attempt-0001: runs=1", text_report)
            self.assertIn("run-0003 worker [completed] task=task-0001 attempt=attempt-0001", text_report)

            json_report = inspector.render_json_report(report)
            json_payload = json.loads(json_report)
            self.assertEqual(json_payload["task_counts"]["completed"], 1)
            self.assertIn("recent_events", json_payload)

            runner.run_collection.rollups_path.unlink()
            rebuilt_report = inspector.build_report(rebuild_rollups=True, max_events=3)
            self.assertIsNotNone(rebuilt_report.rollups)
            self.assertEqual(len(rebuilt_report.recent_events), 3)
            self.assertTrue(runner.run_collection.rollups_path.is_file())

            text_stdout = StringIO()
            text_stderr = StringIO()
            with redirect_stdout(text_stdout), redirect_stderr(text_stderr):
                text_exit_code = inspection_main([str(root), "--max-events", "3", "--max-run-lines", "2"])
            self.assertEqual(text_exit_code, 0)
            self.assertEqual(text_stderr.getvalue(), "")
            self.assertIn("Recent task events:", text_stdout.getvalue())
            self.assertIn("by attempt:", text_stdout.getvalue())
            self.assertIn("attempt-0001: runs=1", text_stdout.getvalue())
            self.assertIn("run-0004", text_stdout.getvalue())
            self.assertNotIn("run-0002", text_stdout.getvalue())

            json_stdout = StringIO()
            json_stderr = StringIO()
            with redirect_stdout(json_stdout), redirect_stderr(json_stderr):
                json_exit_code = inspection_main([str(root), "--json", "--max-events", "3", "--rebuild-rollups"])
            self.assertEqual(json_exit_code, 0)
            self.assertEqual(json_stderr.getvalue(), "")
            cli_payload = json.loads(json_stdout.getvalue())
            self.assertEqual(len(cli_payload["recent_events"]), 3)
            self.assertEqual(cli_payload["task_counts"]["completed"], 1)


if __name__ == "__main__":
    unittest.main()
