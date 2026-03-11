from __future__ import annotations

import asyncio
import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from pydantic_ai.messages import ModelRequest, ModelResponse, TextPart, ToolCallPart, ToolReturnPart
from pydantic_ai.models.function import AgentInfo, FunctionModel
from pydantic_ai.models.test import TestModel

from aftk.agents import (
    DEFAULT_ORCHESTRATOR_USER_PROMPT,
    DEFAULT_WORKER_USER_PROMPT,
    OrchestratorDeps,
    WorkerDeps,
    WorkerReport,
    WorkerTaskBrief,
    build_orchestrator_agent,
    build_worker_agent,
)
from aftk.config import FrameworkConfig
from aftk.project import ProjectSnapshotService
from aftk.runner import FrameworkRunner, RunnerDecisionError
from aftk.storage import RunLogStore, ToolFamily
from aftk.tasks import ArtifactKind, ArtifactRef, Task, TaskPriority, TaskState, TaskStatus


class EmptyToolkitClient:
    pass


def make_config(root: Path) -> FrameworkConfig:
    root.mkdir(parents=True, exist_ok=True)
    (root / "lakefile.toml").write_text('name = "demo"\n', encoding="utf-8")
    (root / "entrypoint.md").write_text("# Demo\nFormalize the project.\n", encoding="utf-8")
    return FrameworkConfig.from_project_root(root)


def make_snapshot(config: FrameworkConfig):
    return ProjectSnapshotService(config).build_snapshot(now=datetime(2026, 1, 1, tzinfo=timezone.utc))


def make_task(task_id: str = "task-0001", *, status: TaskStatus = TaskStatus.READY) -> Task:
    timestamp = datetime(2026, 1, 1, tzinfo=timezone.utc)
    return Task(
        id=task_id,
        title="Prove demo theorem",
        description="Finish the first theorem in Demo.lean.",
        kind="formalization",
        status=status,
        priority=TaskPriority.HIGH,
        acceptance_criteria=["The theorem compiles."],
        depends_on=[],
        blockers=[],
        scope=[ArtifactRef(kind=ArtifactKind.FILE, value="Demo.lean")],
        context_summary="Focus on the first unfinished proof.",
        notes=[],
        created_by="initializer",
        updated_by="initializer",
        current_attempt_id=None,
        attempt_count=0,
        created_at=timestamp,
        updated_at=timestamp,
    )


class RuntimeAgentTests(unittest.TestCase):
    def test_orchestrator_agent_includes_task_snapshot_and_read_only_tools(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            (root / "Demo.lean").write_text("theorem demo : True := trivial\n", encoding="utf-8")
            snapshot = make_snapshot(config)
            task = make_task()
            task_state = TaskState(
                revision=3,
                tasks={task.id: task},
                created_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
                updated_at=datetime(2026, 1, 2, tzinfo=timezone.utc),
            )
            last_report = WorkerReport(
                outcome="partial",
                summary="Made partial progress after inspecting Demo.lean.",
                evidence=["The theorem body still needs a proof term."],
            )
            captured: dict[str, object] = {}

            def model_function(messages: list[ModelRequest | ModelResponse], info: AgentInfo) -> ModelResponse:
                request = messages[-1]
                assert isinstance(request, ModelRequest)
                captured["instructions"] = request.instructions or ""
                captured["tool_names"] = {tool.name for tool in info.function_tools}
                return ModelResponse(
                    parts=[
                        TextPart(
                            content=json.dumps(
                                {
                                    "project_done": False,
                                    "selected_task_id": "task-0001",
                                    "worker_brief": {
                                        "task_id": "task-0001",
                                        "title": "Prove demo theorem",
                                        "description": "Finish the first theorem in Demo.lean.",
                                        "acceptance_criteria": ["The theorem compiles."],
                                        "scope": [{"kind": "file", "value": "Demo.lean"}],
                                        "local_context": "Demo.lean contains one unfinished theorem.",
                                        "suggested_starting_points": ["Read Demo.lean", "Check the current goal state"],
                                    },
                                    "new_tasks": [],
                                    "task_patches": [],
                                    "rationale": "The only task is ready and should be executed next.",
                                }
                            )
                        )
                    ]
                )

            agent = build_orchestrator_agent(FunctionModel(model_function, model_name="function:orchestrator"))
            result = agent.run_sync(
                DEFAULT_ORCHESTRATOR_USER_PROMPT,
                deps=OrchestratorDeps(
                    config=config,
                    project_snapshot=snapshot,
                    task_snapshot=task_state,
                    toolkit_client=EmptyToolkitClient(),  # type: ignore[arg-type]
                    last_worker_report=last_report,
                ),
            )

            instructions = captured["instructions"]
            tool_names = captured["tool_names"]
            assert isinstance(instructions, str)
            assert isinstance(tool_names, set)

            self.assertEqual(result.output.selected_task_id, "task-0001")
            self.assertIn("Current task snapshot:", instructions)
            self.assertIn("task-0001 [ready] Prove demo theorem", instructions)
            self.assertIn("Latest worker report:", instructions)
            self.assertIn("Made partial progress after inspecting Demo.lean.", instructions)
            self.assertIn("read_entrypoint", tool_names)
            self.assertIn("knowledgebase_status", tool_names)
            self.assertNotIn("write_file", tool_names)
            self.assertNotIn("lake_build", tool_names)

    def test_worker_agent_includes_task_brief_and_worker_tools(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            (root / "Demo.lean").write_text("theorem demo : True := trivial\n", encoding="utf-8")
            snapshot = make_snapshot(config)
            brief = WorkerTaskBrief.from_task(
                make_task(),
                local_context="Focus on Demo.lean lines 1-20.",
                suggested_starting_points=["Read Demo.lean", "Run lake build after editing"],
            )
            captured: dict[str, object] = {}

            def model_function(messages: list[ModelRequest | ModelResponse], info: AgentInfo) -> ModelResponse:
                request = messages[-1]
                assert isinstance(request, ModelRequest)
                captured["instructions"] = request.instructions or ""
                captured["tool_names"] = {tool.name for tool in info.function_tools}
                return ModelResponse(
                    parts=[
                        TextPart(
                            content=json.dumps(
                                {
                                    "outcome": "completed",
                                    "summary": "Finished the local task and validated the result.",
                                    "evidence": ["Demo.lean was updated successfully."],
                                    "changed_artifacts": [{"kind": "file", "value": "Demo.lean"}],
                                    "followup_tasks": [],
                                    "blockers": [],
                                    "handoff_notes": "No additional follow-up is required.",
                                }
                            )
                        )
                    ]
                )

            agent = build_worker_agent(FunctionModel(model_function, model_name="function:worker"))
            result = agent.run_sync(
                DEFAULT_WORKER_USER_PROMPT,
                deps=WorkerDeps(
                    config=config,
                    project_snapshot=snapshot,
                    task_brief=brief,
                    toolkit_client=EmptyToolkitClient(),  # type: ignore[arg-type]
                ),
            )

            instructions = captured["instructions"]
            tool_names = captured["tool_names"]
            assert isinstance(instructions, str)
            assert isinstance(tool_names, set)

            self.assertEqual(result.output.summary, "Finished the local task and validated the result.")
            self.assertIn("Task id: task-0001", instructions)
            self.assertIn("Title: Prove demo theorem", instructions)
            self.assertIn("Local context: Focus on Demo.lean lines 1-20.", instructions)
            self.assertIn("Suggested starting points: Read Demo.lean, Run lake build after editing", instructions)
            self.assertIn("read_entrypoint", tool_names)
            self.assertIn("knowledgebase_status", tool_names)
            self.assertIn("append_to_file", tool_names)
            self.assertIn("lake_build", tool_names)


class RunnerIntegrationTests(unittest.TestCase):
    def test_runner_executes_initializer_worker_cycle_and_persists_logs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            (root / "Demo.lean").write_text("theorem demo : True := trivial\n", encoding="utf-8")
            runner = FrameworkRunner(config)

            initializer_model = TestModel(
                call_tools=[],
                custom_output_args={
                    "project_summary": "Demo project with one Lean theorem.",
                    "assumptions": ["The Lean environment already works."],
                    "risks": ["The project may still need more theorems later."],
                    "initial_tasks": [
                        {
                            "title": "Update Demo.lean",
                            "description": "Make the first tracked edit in Demo.lean.",
                            "kind": "formalization",
                            "acceptance_criteria": ["Demo.lean records the worker edit."],
                            "scope": [{"kind": "file", "value": "Demo.lean"}],
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
                            "title": "Update Demo.lean",
                            "description": "Make the first tracked edit in Demo.lean.",
                            "acceptance_criteria": ["Demo.lean records the worker edit."],
                            "scope": [{"kind": "file", "value": "Demo.lean"}],
                            "local_context": "Append a short audit comment to Demo.lean.",
                            "suggested_starting_points": ["Append a comment", "Report the changed artifact"],
                        },
                        "new_tasks": [],
                        "task_patches": [],
                        "rationale": "The initialized task is ready and should be executed next.",
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
                                "append_notes": ["Worker finished the requested edit."],
                            }
                        ],
                        "rationale": "The worker finished the only task, so the project is complete.",
                        "completion_summary": "The demo project has completed its only task.",
                    }
                return ModelResponse(parts=[TextPart(content=json.dumps(payload))])

            def worker_function(messages: list[ModelRequest | ModelResponse], info: AgentInfo) -> ModelResponse:
                has_tool_return = any(
                    isinstance(message, ModelRequest)
                    and any(isinstance(part, ToolReturnPart) for part in message.parts)
                    for message in messages
                )
                if not has_tool_return:
                    return ModelResponse(
                        parts=[
                            ToolCallPart(
                                tool_name="append_to_file",
                                args={"path": "Demo.lean", "content": "\n-- worker touched Demo.lean\n"},
                                tool_call_id="call-append-demo",
                            )
                        ]
                    )
                payload = {
                    "outcome": "completed",
                    "summary": "Appended an audit comment to Demo.lean.",
                    "evidence": ["append_to_file updated Demo.lean"],
                    "changed_artifacts": [{"kind": "file", "value": "Demo.lean"}],
                    "followup_tasks": [],
                    "blockers": [],
                    "handoff_notes": "The requested local edit is complete.",
                }
                return ModelResponse(parts=[TextPart(content=json.dumps(payload))])

            result = asyncio.run(
                runner.run(
                    toolkit_client=EmptyToolkitClient(),  # type: ignore[arg-type]
                    initializer_model=initializer_model,
                    orchestrator_model=FunctionModel(orchestrator_function, model_name="function:orchestrator"),
                    worker_model=FunctionModel(worker_function, model_name="function:worker"),
                    max_iterations=4,
                )
            )

            self.assertTrue(result.project_done)
            self.assertEqual(result.completion_summary, "The demo project has completed its only task.")
            self.assertEqual(result.initialization_run_id, "run-0001")
            self.assertEqual(result.orchestrator_run_ids, ["run-0002", "run-0004"])
            self.assertEqual(result.worker_run_ids, ["run-0003"])

            state = runner.task_service.load_state()
            self.assertEqual(state.tasks["task-0001"].status, TaskStatus.COMPLETED)
            self.assertIn("worker touched Demo.lean", (root / "Demo.lean").read_text(encoding="utf-8"))

            attempt = runner.task_service.store.load_attempt("attempt-0001")
            self.assertEqual(attempt.run_id, "run-0003")
            self.assertEqual(attempt.report_path, ".aftk/runs/run-0003/result.json")
            self.assertEqual(attempt.transcript_path, ".aftk/runs/run-0003/messages.json")
            self.assertEqual(attempt.llm_call_log_path, ".aftk/runs/run-0003/llm-calls.jsonl")
            self.assertEqual(attempt.tool_call_log_path, ".aftk/runs/run-0003/tool-calls.jsonl")

            run_ids = runner.run_collection.list_run_ids()
            self.assertEqual(run_ids, ["run-0001", "run-0002", "run-0003", "run-0004"])
            worker_store = RunLogStore(config, "run-0003")
            tool_calls = worker_store.load_tool_calls()
            self.assertEqual(len(tool_calls), 1)
            self.assertEqual(tool_calls[0].tool_name, "append_to_file")
            self.assertEqual(tool_calls[0].tool_family, ToolFamily.CODING)
            self.assertTrue(worker_store.coding_actions_path.is_file())
            self.assertIn("append_to_file", worker_store.coding_actions_path.read_text(encoding="utf-8"))
            self.assertTrue(runner.run_collection.rollups_path.is_file())

    def test_runner_rejects_invalid_project_done_decision(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            (root / "Demo.lean").write_text("theorem demo : True := trivial\n", encoding="utf-8")
            runner = FrameworkRunner(config)

            initializer_model = TestModel(
                call_tools=[],
                custom_output_args={
                    "project_summary": "Demo project with one Lean theorem.",
                    "assumptions": [],
                    "risks": [],
                    "initial_tasks": [
                        {
                            "title": "Update Demo.lean",
                            "description": "Make the first tracked edit in Demo.lean.",
                            "kind": "formalization",
                            "acceptance_criteria": ["Demo.lean records the worker edit."],
                            "scope": [{"kind": "file", "value": "Demo.lean"}],
                        }
                    ],
                },
            )
            orchestrator_model = TestModel(
                call_tools=[],
                custom_output_args={
                    "project_done": True,
                    "selected_task_id": None,
                    "worker_brief": None,
                    "new_tasks": [],
                    "task_patches": [],
                    "rationale": "Everything is already complete.",
                    "completion_summary": "Done.",
                },
            )

            with self.assertRaises(RunnerDecisionError):
                asyncio.run(
                    runner.run(
                        toolkit_client=EmptyToolkitClient(),  # type: ignore[arg-type]
                        initializer_model=initializer_model,
                        orchestrator_model=orchestrator_model,
                        worker_model=TestModel(call_tools=[], custom_output_args={
                            "outcome": "completed",
                            "summary": "unused",
                            "evidence": [],
                            "changed_artifacts": [],
                            "followup_tasks": [],
                            "blockers": [],
                        }),
                        max_iterations=2,
                    )
                )

            self.assertEqual(runner.run_collection.list_run_ids(), ["run-0001", "run-0002"])
            orchestrator_record = runner.run_collection.run_store("run-0002").load_run_record()
            self.assertEqual(orchestrator_record.status.value, "completed")
            state = runner.task_service.load_state()
            self.assertEqual(state.tasks["task-0001"].status, TaskStatus.READY)


if __name__ == "__main__":
    unittest.main()
