from __future__ import annotations

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any, cast

from pydantic_ai import Agent
from pydantic_ai._run_context import RunContext
from pydantic_ai.models.test import TestModel
from pydantic_ai.usage import RunUsage

from aftk import AsyncAftkClient
from aftk.tasks import (
    InMemoryTaskRunStore,
    MissingDependencyError,
    TaskConflictError,
    TaskCycleError,
    TaskManager,
    TaskNotFoundError,
    TaskSpec,
    TaskTransitionError,
)
from aftk.toolkits.aftk import AftkToolkit
from aftk.toolkits.coding import CodingToolkit
from aftk.toolkits.tasks import TaskToolFailure, TaskToolSuccess, TaskToolkit
from aftk.toolkits.tasks.errors import TaskToolkitExecutionError, failure_from_exception


class DummyClient:
    pass


def build_manager() -> TaskManager:
    manager = TaskManager.create(InMemoryTaskRunStore(), "run-1", metadata={"project": "demo"})
    manager.add_tasks(
        [
            TaskSpec(id="task-1", kind="seed", title="Seed task", priority=2),
            TaskSpec(id="task-2", kind="formalize", title="Current task", depends_on=["task-1"], priority=5),
            TaskSpec(id="task-3", kind="review", title="Blocked task", depends_on=["task-2"], priority=1),
        ]
    )
    manager.claim_task("task-1", runner_id="bootstrap")
    manager.complete_task("task-1", summary="bootstrap complete")
    return manager


class ToolkitSchemaTests(unittest.IsolatedAsyncioTestCase):
    async def test_agent_exposes_expected_executor_tools(self) -> None:
        model = TestModel(call_tools=[], custom_output_text="ok")
        toolkit = TaskToolkit(build_manager(), current_task_id="task-2")
        agent = Agent(model, toolsets=[toolkit])

        result = await agent.run("hello")

        self.assertEqual(result.output, "ok")
        assert model.last_model_request_parameters is not None
        tool_defs = {tool.name: tool for tool in model.last_model_request_parameters.function_tools}

        self.assertEqual(
            set(tool_defs),
            {
                "task_current",
                "task_get",
                "task_run_summary",
                "task_list_ready",
                "task_list_blocked",
                "task_add_note",
                "task_add_artifact",
                "task_propose_tasks",
            },
        )
        self.assertTrue(tool_defs["task_current"].sequential)
        self.assertEqual(
            tool_defs["task_current"].metadata,
            {"source": "tasks", "layer": "task_run", "mutates": False, "advanced": False, "mode": "executor"},
        )
        self.assertEqual(
            tool_defs["task_add_note"].parameters_json_schema["properties"]["text"]["description"],
            "Plain-text note content to append to the task.",
        )
        self.assertIn("proposals", tool_defs["task_propose_tasks"].parameters_json_schema["properties"])

    async def test_read_only_flag_hides_mutating_tools(self) -> None:
        model = TestModel(call_tools=[], custom_output_text="ok")
        toolkit = TaskToolkit(build_manager(), current_task_id="task-2", read_only=True)
        agent = Agent(model, toolsets=[toolkit])

        await agent.run("hello")

        assert model.last_model_request_parameters is not None
        names = {tool.name for tool in model.last_model_request_parameters.function_tools}
        self.assertEqual(
            names,
            {"task_current", "task_get", "task_run_summary", "task_list_ready", "task_list_blocked"},
        )


class ToolkitBehaviorTests(unittest.IsolatedAsyncioTestCase):
    def _context(self) -> RunContext[Any]:
        return RunContext(deps=None, model=TestModel(call_tools=[]), usage=RunUsage())

    async def _call_tool(self, toolkit: TaskToolkit, name: str, args: dict[str, Any]) -> Any:
        ctx = self._context()
        tools = await toolkit.get_tools(ctx)
        tool = tools[name]
        validated_args = tool.args_validator.validate_python(args)
        return await toolkit.call_tool(name, validated_args, ctx, tool)

    async def test_read_tools_return_detail_and_summary_views(self) -> None:
        manager = build_manager()
        toolkit = TaskToolkit(manager, current_task_id="task-2")

        current = await self._call_tool(toolkit, "task_current", {})
        self.assertIsInstance(current, TaskToolSuccess)
        self.assertEqual(current.data["id"], "task-2")
        self.assertEqual(current.data["scheduler_status"], "ready")
        self.assertEqual(current.data["dependencies"][0]["id"], "task-1")
        self.assertEqual(current.data["dependencies"][0]["scheduler_status"], "completed")

        detail = await self._call_tool(toolkit, "task_get", {"task_id": "task-3"})
        self.assertIsInstance(detail, TaskToolSuccess)
        self.assertEqual(detail.data["id"], "task-3")
        self.assertEqual(detail.data["scheduler_status"], "blocked")
        self.assertEqual(detail.data["depends_on"], ["task-2"])

        summary = await self._call_tool(toolkit, "task_run_summary", {"limit": 2})
        self.assertIsInstance(summary, TaskToolSuccess)
        self.assertEqual(summary.data["run_id"], "run-1")
        self.assertEqual(summary.data["total_tasks"], 3)
        self.assertEqual(summary.data["tasks_returned"], 2)
        self.assertEqual(summary.data["counts_by_scheduler_status"]["ready"], 1)
        self.assertEqual(summary.data["counts_by_scheduler_status"]["blocked"], 1)
        self.assertEqual(summary.data["counts_by_scheduler_status"]["completed"], 1)

        ready = await self._call_tool(toolkit, "task_list_ready", {})
        self.assertIsInstance(ready, TaskToolSuccess)
        self.assertEqual([task["id"] for task in ready.data["tasks"]], ["task-2"])

        blocked = await self._call_tool(toolkit, "task_list_blocked", {})
        self.assertIsInstance(blocked, TaskToolSuccess)
        self.assertEqual([task["id"] for task in blocked.data["tasks"]], ["task-3"])

    async def test_missing_task_and_missing_current_task_return_structured_failures(self) -> None:
        manager = build_manager()
        toolkit = TaskToolkit(manager, current_task_id="task-2")

        missing = await self._call_tool(toolkit, "task_get", {"task_id": "missing"})
        self.assertIsInstance(missing, TaskToolFailure)
        self.assertEqual(missing.error.kind, "task_not_found")
        self.assertEqual(missing.error.details["task_id"], "missing")

        unbound = TaskToolkit(manager)
        no_current = await self._call_tool(unbound, "task_current", {})
        self.assertIsInstance(no_current, TaskToolFailure)
        self.assertEqual(no_current.error.kind, "no_current_task")
        self.assertTrue(no_current.error.retryable)

    async def test_write_tools_persist_notes_artifacts_and_proposals(self) -> None:
        manager = build_manager()
        toolkit = TaskToolkit(manager, current_task_id="task-2")

        note = await self._call_tool(
            toolkit,
            "task_add_note",
            {"text": "Need to inspect imports.", "metadata": {"author": "worker"}},
        )
        self.assertIsInstance(note, TaskToolSuccess)
        self.assertEqual(manager.get_task("task-2").artifacts[-1].kind, "note")
        self.assertEqual(manager.get_task("task-2").artifacts[-1].value, "Need to inspect imports.")
        self.assertEqual(note.data["artifacts"][-1]["metadata"]["author"], "worker")

        artifact = await self._call_tool(
            toolkit,
            "task_add_artifact",
            {
                "kind": "analysis",
                "label": "dependency scan",
                "value": {"imports": ["Mathlib"]},
                "metadata": {"source": "worker"},
            },
        )
        self.assertIsInstance(artifact, TaskToolSuccess)
        self.assertEqual(manager.get_task("task-2").artifacts[-1].kind, "analysis")
        self.assertEqual(manager.get_task("task-2").artifacts[-1].label, "dependency scan")

        proposal = await self._call_tool(
            toolkit,
            "task_propose_tasks",
            {
                "rationale": "Discovered an additional follow-up theorem.",
                "proposals": [
                    {
                        "id": "task-4",
                        "kind": "formalize_follow_up",
                        "title": "Formalize follow-up theorem",
                        "depends_on": ["task-2"],
                        "payload": {"ref": "follow.up.theorem"},
                    }
                ],
            },
        )
        self.assertIsInstance(proposal, TaskToolSuccess)
        last_artifact = manager.get_task("task-2").artifacts[-1]
        self.assertEqual(last_artifact.kind, "task_proposal_batch")
        self.assertEqual(last_artifact.value["proposals"][0]["id"], "task-4")
        self.assertEqual(last_artifact.metadata["source_task_id"], "task-2")
        self.assertEqual(last_artifact.metadata["proposal_count"], 1)
        self.assertEqual(proposal.data["artifacts"][-1]["kind"], "task_proposal_batch")

    async def test_executor_mode_rejects_cross_task_writes(self) -> None:
        manager = build_manager()
        toolkit = TaskToolkit(manager, current_task_id="task-2")

        result = await self._call_tool(
            toolkit,
            "task_add_note",
            {"task_id": "task-3", "text": "should not be allowed"},
        )

        self.assertIsInstance(result, TaskToolFailure)
        self.assertEqual(result.error.kind, "cross_task_write_forbidden")
        self.assertEqual(result.error.details["current_task_id"], "task-2")
        self.assertEqual(result.error.details["task_id"], "task-3")

    async def test_duplicate_or_conflicting_proposals_return_failures(self) -> None:
        manager = build_manager()
        toolkit = TaskToolkit(manager, current_task_id="task-2")

        duplicate = await self._call_tool(
            toolkit,
            "task_propose_tasks",
            {
                "proposals": [
                    {"id": "task-4", "kind": "follow_up", "title": "First"},
                    {"id": "task-4", "kind": "follow_up", "title": "Second"},
                ]
            },
        )
        self.assertIsInstance(duplicate, TaskToolFailure)
        self.assertEqual(duplicate.error.kind, "invalid_payload")

        conflict = await self._call_tool(
            toolkit,
            "task_propose_tasks",
            {"proposals": [{"id": "task-3", "kind": "follow_up", "title": "Conflict"}]},
        )
        self.assertIsInstance(conflict, TaskToolFailure)
        self.assertEqual(conflict.error.kind, "task_conflict")


class ErrorMappingTests(unittest.TestCase):
    def test_failure_from_exception_maps_expected_error_kinds(self) -> None:
        self.assertEqual(
            failure_from_exception("task_get", TaskNotFoundError("missing")).error.kind,
            "task_not_found",
        )
        self.assertEqual(
            failure_from_exception("task_add_note", TaskTransitionError("bad transition")).error.kind,
            "invalid_transition",
        )
        self.assertEqual(
            failure_from_exception("task_add_note", TaskConflictError("duplicate task")).error.kind,
            "task_conflict",
        )
        self.assertEqual(
            failure_from_exception("task_add_dependency", MissingDependencyError("missing dep")).error.kind,
            "missing_dependency",
        )
        self.assertEqual(
            failure_from_exception("task_add_dependency", TaskCycleError("cycle")).error.kind,
            "cycle_detected",
        )
        self.assertEqual(
            failure_from_exception(
                "task_current",
                TaskToolkitExecutionError(kind="no_current_task", message="missing", retryable=True),
            ).error.kind,
            "no_current_task",
        )
        self.assertEqual(
            failure_from_exception("task_get", Exception("boom")).error.kind,
            "task_tool_internal_error",
        )


class ToolkitCompositionTests(unittest.IsolatedAsyncioTestCase):
    async def test_task_toolkit_composes_with_other_toolkits(self) -> None:
        manager = build_manager()
        with TemporaryDirectory() as tmpdir:
            model = TestModel(call_tools=[], custom_output_text="ok")
            agent = Agent(
                model,
                toolsets=[
                    CodingToolkit(cwd=Path(tmpdir), include_search=False),
                    AftkToolkit(
                        cast(AsyncAftkClient, DummyClient()),
                        include_knowledgebase=False,
                        include_informal=False,
                    ),
                    TaskToolkit(manager, current_task_id="task-2"),
                ],
            )

            result = await agent.run("hello")

            self.assertEqual(result.output, "ok")
            assert model.last_model_request_parameters is not None
            names = {tool.name for tool in model.last_model_request_parameters.function_tools}
            self.assertIn("read", names)
            self.assertIn("lean_get_hover", names)
            self.assertIn("task_current", names)


if __name__ == "__main__":
    unittest.main()
