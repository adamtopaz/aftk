from __future__ import annotations

import unittest
from typing import Any

from pydantic_ai import Agent
from pydantic_ai._run_context import RunContext
from pydantic_ai.models.test import TestModel
from pydantic_ai.usage import RunUsage

from aftk.tasks import (
    InMemoryTaskRunStore,
    MissingDependencyError,
    TaskArtifact,
    TaskConflictError,
    TaskCycleError,
    TaskExecutionResult,
    TaskExecutionStatus,
    TaskLifecycleStatus,
    TaskManager,
    TaskNotFoundError,
    TaskRecord,
    TaskSpec,
    TaskTransitionError,
)
from aftk.toolkits.orchestrator import (
    OrchestratorToolFailure,
    OrchestratorToolSuccess,
    OrchestratorToolkit,
)
from aftk.toolkits.orchestrator.errors import OrchestratorToolkitExecutionError, failure_from_exception
from aftk.toolkits.tasks import TaskToolSuccess, TaskToolkit


class FakeWorkerRunner:
    def __init__(self) -> None:
        self.name = "fake-runner"
        self.calls: list[tuple[str, str, str | None]] = []
        self.results: dict[str, TaskExecutionResult | Exception] = {}

    async def run_task(self, manager: TaskManager, task: TaskRecord) -> TaskExecutionResult:
        self.calls.append((task.id, task.status.value, task.claimed_by))
        result = self.results.get(task.id)
        if isinstance(result, Exception):
            raise result
        if result is None:
            return TaskExecutionResult(status=TaskExecutionStatus.completed, summary=f"completed {task.id}")
        return result


def build_manager() -> TaskManager:
    manager = TaskManager.create(InMemoryTaskRunStore(), "run-1", metadata={"project": "demo"})
    manager.add_tasks(
        [
            TaskSpec(id="task-1", kind="seed", title="Completed task", priority=10),
            TaskSpec(id="task-2", kind="formalize", title="Ready task", depends_on=["task-1"], priority=5),
            TaskSpec(id="task-3", kind="review", title="Blocked task", depends_on=["task-2"], priority=1),
            TaskSpec(id="task-4", kind="repair", title="Failed task", priority=4, max_attempts=2),
            TaskSpec(id="task-5", kind="check", title="Running task", priority=3),
        ]
    )
    manager.claim_task("task-1", runner_id="bootstrap")
    manager.complete_task("task-1", summary="seed complete")
    manager.claim_task("task-4", runner_id="worker-fail")
    manager.fail_task("task-4", error_message="boom", summary="attempt failed")
    manager.claim_task("task-5", runner_id="worker-run")
    return manager


def build_mutation_manager() -> TaskManager:
    manager = TaskManager.create(InMemoryTaskRunStore(), "run-1", metadata={"project": "demo"})
    manager.add_tasks(
        [
            TaskSpec(id="task-1", kind="seed", title="Seed task", priority=10),
            TaskSpec(id="task-2", kind="formalize", title="Primary task", depends_on=["task-1"], priority=5),
            TaskSpec(id="task-3", kind="review", title="Secondary task", priority=4, max_attempts=2),
        ]
    )
    manager.claim_task("task-1", runner_id="bootstrap")
    manager.complete_task("task-1", summary="seed complete")
    return manager


class ToolkitSchemaTests(unittest.IsolatedAsyncioTestCase):
    async def test_agent_exposes_expected_tools_without_dispatch_by_default(self) -> None:
        model = TestModel(call_tools=[], custom_output_text="ok")
        toolkit = OrchestratorToolkit(build_manager())
        agent = Agent(model, toolsets=[toolkit])

        result = await agent.run("hello")

        self.assertEqual(result.output, "ok")
        assert model.last_model_request_parameters is not None
        tool_defs = {tool.name: tool for tool in model.last_model_request_parameters.function_tools}

        self.assertEqual(
            set(tool_defs),
            {
                "orch_run_summary",
                "orch_task_table",
                "orch_get_task",
                "orch_list_ready",
                "orch_list_blocked",
                "orch_list_running",
                "orch_list_failed",
                "orch_list_terminal",
                "orch_list_incomplete",
                "orch_validate_graph",
                "orch_add_task",
                "orch_add_tasks",
                "orch_add_dependency",
                "orch_attach_note",
                "orch_attach_artifact",
                "orch_claim_task",
                "orch_complete_task",
                "orch_fail_task",
                "orch_cancel_task",
                "orch_requeue_task",
                "orch_list_proposals",
                "orch_get_proposal",
                "orch_apply_proposal",
                "orch_reject_proposal",
            },
        )
        self.assertTrue(tool_defs["orch_run_summary"].sequential)
        self.assertEqual(
            tool_defs["orch_run_summary"].metadata,
            {
                "source": "orchestrator",
                "layer": "task_run",
                "mutates": False,
                "advanced": False,
                "role": "orchestrator",
                "dispatch": False,
            },
        )
        self.assertEqual(
            tool_defs["orch_add_task"].parameters_json_schema["properties"]["task"]["description"],
            "Validated task specification to add to the run.",
        )
        self.assertNotIn("orch_dispatch_task", tool_defs)

    async def test_worker_runner_and_read_only_flags_filter_dispatch_and_mutations(self) -> None:
        dispatch_model = TestModel(call_tools=[], custom_output_text="ok")
        dispatch_agent = Agent(dispatch_model, toolsets=[OrchestratorToolkit(build_manager(), worker_runner=FakeWorkerRunner())])

        await dispatch_agent.run("hello")

        assert dispatch_model.last_model_request_parameters is not None
        dispatch_names = {tool.name for tool in dispatch_model.last_model_request_parameters.function_tools}
        self.assertIn("orch_dispatch_task", dispatch_names)
        self.assertIn("orch_dispatch_next_ready", dispatch_names)

        read_only_model = TestModel(call_tools=[], custom_output_text="ok")
        read_only_agent = Agent(
            read_only_model,
            toolsets=[OrchestratorToolkit(build_manager(), worker_runner=FakeWorkerRunner(), read_only=True)],
        )

        await read_only_agent.run("hello")

        assert read_only_model.last_model_request_parameters is not None
        read_only_names = {tool.name for tool in read_only_model.last_model_request_parameters.function_tools}
        self.assertEqual(
            read_only_names,
            {
                "orch_run_summary",
                "orch_task_table",
                "orch_get_task",
                "orch_list_ready",
                "orch_list_blocked",
                "orch_list_running",
                "orch_list_failed",
                "orch_list_terminal",
                "orch_list_incomplete",
                "orch_validate_graph",
                "orch_list_proposals",
                "orch_get_proposal",
            },
        )


class ToolkitBehaviorTests(unittest.IsolatedAsyncioTestCase):
    def _context(self) -> RunContext[Any]:
        return RunContext(deps=None, model=TestModel(call_tools=[]), usage=RunUsage())

    async def _call_tool(self, toolkit: Any, name: str, args: dict[str, Any]) -> Any:
        ctx = self._context()
        tools = await toolkit.get_tools(ctx)
        tool = tools[name]
        validated_args = tool.args_validator.validate_python(args)
        return await toolkit.call_tool(name, validated_args, ctx, tool)

    async def _record_worker_proposal(self, manager: TaskManager) -> str:
        worker = TaskToolkit(manager, current_task_id="task-2")
        proposal = await self._call_tool(
            worker,
            "task_propose_tasks",
            {
                "rationale": "Discovered a follow-up task.",
                "proposals": [
                    {
                        "id": "task-4",
                        "kind": "follow_up",
                        "title": "Follow-up task",
                        "depends_on": ["task-2"],
                        "payload": {"ref": "follow.up"},
                    }
                ],
            },
        )
        self.assertIsInstance(proposal, TaskToolSuccess)
        orch = OrchestratorToolkit(manager)
        listing = await self._call_tool(orch, "orch_list_proposals", {})
        self.assertIsInstance(listing, OrchestratorToolSuccess)
        return listing.data["proposals"][0]["proposal_id"]

    async def test_read_tools_return_run_global_views(self) -> None:
        manager = build_manager()
        toolkit = OrchestratorToolkit(manager)

        summary = await self._call_tool(toolkit, "orch_run_summary", {"limit": 3})
        self.assertIsInstance(summary, OrchestratorToolSuccess)
        self.assertEqual(summary.data["run_id"], "run-1")
        self.assertEqual(summary.data["total_tasks"], 5)
        self.assertEqual(summary.data["tasks_returned"], 3)
        self.assertEqual(summary.data["counts_by_scheduler_status"]["ready"], 1)
        self.assertEqual(summary.data["counts_by_scheduler_status"]["blocked"], 1)
        self.assertEqual(summary.data["counts_by_scheduler_status"]["running"], 1)
        self.assertEqual(summary.data["counts_by_scheduler_status"]["failed"], 1)
        self.assertEqual(summary.data["counts_by_scheduler_status"]["completed"], 1)

        table = await self._call_tool(toolkit, "orch_task_table", {})
        self.assertIsInstance(table, OrchestratorToolSuccess)
        self.assertEqual(table.data["total_tasks"], 5)

        detail = await self._call_tool(toolkit, "orch_get_task", {"task_id": "task-2"})
        self.assertIsInstance(detail, OrchestratorToolSuccess)
        self.assertEqual(detail.data["id"], "task-2")
        self.assertEqual(detail.data["scheduler_status"], "ready")
        self.assertEqual(detail.data["dependencies"][0]["id"], "task-1")
        self.assertEqual(detail.data["dependencies"][0]["scheduler_status"], "completed")

        ready = await self._call_tool(toolkit, "orch_list_ready", {})
        blocked = await self._call_tool(toolkit, "orch_list_blocked", {})
        running = await self._call_tool(toolkit, "orch_list_running", {})
        failed = await self._call_tool(toolkit, "orch_list_failed", {})
        terminal = await self._call_tool(toolkit, "orch_list_terminal", {})
        incomplete = await self._call_tool(toolkit, "orch_list_incomplete", {})
        validate = await self._call_tool(toolkit, "orch_validate_graph", {})

        self.assertEqual([task["id"] for task in ready.data["tasks"]], ["task-2"])
        self.assertEqual([task["id"] for task in blocked.data["tasks"]], ["task-3"])
        self.assertEqual([task["id"] for task in running.data["tasks"]], ["task-5"])
        self.assertEqual([task["id"] for task in failed.data["tasks"]], ["task-4"])
        self.assertEqual([task["id"] for task in terminal.data["tasks"]], ["task-1", "task-4"])
        self.assertEqual([task["id"] for task in incomplete.data["tasks"]], ["task-2", "task-5", "task-3"])
        self.assertEqual(validate.data["valid"], True)
        self.assertEqual(validate.data["total_dependencies"], 2)

    async def test_lifecycle_and_graph_mutation_tools_persist_state(self) -> None:
        manager = build_mutation_manager()
        toolkit = OrchestratorToolkit(manager)

        add_one = await self._call_tool(
            toolkit,
            "orch_add_task",
            {
                "task": {
                    "id": "task-4",
                    "kind": "follow_up",
                    "title": "Follow-up",
                    "depends_on": ["task-2"],
                    "payload": {"target": "lemma"},
                }
            },
        )
        self.assertIsInstance(add_one, OrchestratorToolSuccess)
        self.assertEqual(manager.get_task("task-4").depends_on, ["task-2"])

        add_many = await self._call_tool(
            toolkit,
            "orch_add_tasks",
            {
                "tasks": [
                    {"id": "task-5", "kind": "helper", "title": "Helper task"},
                    {"id": "task-6", "kind": "helper", "title": "Helper child"},
                ]
            },
        )
        self.assertIsInstance(add_many, OrchestratorToolSuccess)
        self.assertEqual({task["id"] for task in add_many.data["tasks"]}, {"task-5", "task-6"})

        add_dep = await self._call_tool(
            toolkit,
            "orch_add_dependency",
            {"task_id": "task-6", "dependency_id": "task-5"},
        )
        self.assertIsInstance(add_dep, OrchestratorToolSuccess)
        self.assertEqual(manager.get_task("task-6").depends_on, ["task-5"])

        note = await self._call_tool(
            toolkit,
            "orch_attach_note",
            {"task_id": "task-2", "text": "Ready for orchestration.", "metadata": {"author": "orch"}},
        )
        self.assertIsInstance(note, OrchestratorToolSuccess)
        self.assertEqual(manager.get_task("task-2").artifacts[-1].kind, "note")

        artifact = await self._call_tool(
            toolkit,
            "orch_attach_artifact",
            {
                "task_id": "task-2",
                "kind": "analysis",
                "label": "planner note",
                "value": {"ready": True},
            },
        )
        self.assertIsInstance(artifact, OrchestratorToolSuccess)
        self.assertEqual(manager.get_task("task-2").artifacts[-1].kind, "analysis")

        claim = await self._call_tool(toolkit, "orch_claim_task", {"task_id": "task-2", "runner_id": "orch"})
        self.assertIsInstance(claim, OrchestratorToolSuccess)
        self.assertEqual(manager.get_task("task-2").status, TaskLifecycleStatus.running)

        complete = await self._call_tool(
            toolkit,
            "orch_complete_task",
            {
                "task_id": "task-2",
                "summary": "finished primary task",
                "artifacts": [{"kind": "output", "value": "proof"}],
                "metadata": {"reviewed": True},
            },
        )
        self.assertIsInstance(complete, OrchestratorToolSuccess)
        self.assertEqual(manager.get_task("task-2").status, TaskLifecycleStatus.completed)
        self.assertEqual(manager.get_task("task-2").artifacts[-1].value, "proof")
        self.assertEqual(manager.get_task("task-2").metadata["reviewed"], True)

        claim_secondary = await self._call_tool(toolkit, "orch_claim_task", {"task_id": "task-3"})
        self.assertIsInstance(claim_secondary, OrchestratorToolSuccess)
        fail = await self._call_tool(
            toolkit,
            "orch_fail_task",
            {
                "task_id": "task-3",
                "error_message": "failed review",
                "summary": "proof rejected",
                "artifacts": [{"kind": "log", "value": "details"}],
            },
        )
        self.assertIsInstance(fail, OrchestratorToolSuccess)
        self.assertEqual(manager.get_task("task-3").status, TaskLifecycleStatus.failed)
        self.assertEqual(manager.get_task("task-3").last_error, "failed review")

        requeue = await self._call_tool(toolkit, "orch_requeue_task", {"task_id": "task-3"})
        self.assertIsInstance(requeue, OrchestratorToolSuccess)
        self.assertEqual(manager.get_task("task-3").status, TaskLifecycleStatus.pending)
        self.assertIsNone(manager.get_task("task-3").last_error)

        cancel = await self._call_tool(
            toolkit,
            "orch_cancel_task",
            {"task_id": "task-5", "summary": "no longer needed"},
        )
        self.assertIsInstance(cancel, OrchestratorToolSuccess)
        self.assertEqual(manager.get_task("task-5").status, TaskLifecycleStatus.canceled)

    async def test_graph_and_state_errors_return_structured_failures(self) -> None:
        manager = build_mutation_manager()
        toolkit = OrchestratorToolkit(manager)

        duplicate = await self._call_tool(
            toolkit,
            "orch_add_task",
            {"task": {"id": "task-2", "kind": "dup", "title": "Duplicate"}},
        )
        self.assertIsInstance(duplicate, OrchestratorToolFailure)
        self.assertEqual(duplicate.error.kind, "task_conflict")

        missing_dep = await self._call_tool(
            toolkit,
            "orch_add_dependency",
            {"task_id": "task-3", "dependency_id": "missing"},
        )
        self.assertIsInstance(missing_dep, OrchestratorToolFailure)
        self.assertEqual(missing_dep.error.kind, "missing_dependency")

        cycle = await self._call_tool(
            toolkit,
            "orch_add_dependency",
            {"task_id": "task-1", "dependency_id": "task-2"},
        )
        self.assertIsInstance(cycle, OrchestratorToolFailure)
        self.assertEqual(cycle.error.kind, "cycle_detected")

        invalid_transition = await self._call_tool(toolkit, "orch_complete_task", {"task_id": "task-2"})
        self.assertIsInstance(invalid_transition, OrchestratorToolFailure)
        self.assertEqual(invalid_transition.error.kind, "invalid_transition")

    async def test_proposal_workflow_lists_applies_and_rejects_worker_proposals(self) -> None:
        manager = build_mutation_manager()
        proposal_id = await self._record_worker_proposal(manager)
        toolkit = OrchestratorToolkit(manager)

        listing = await self._call_tool(toolkit, "orch_list_proposals", {})
        self.assertIsInstance(listing, OrchestratorToolSuccess)
        self.assertEqual(listing.data["total_proposals"], 1)
        self.assertEqual(listing.data["proposals"][0]["status"], "pending")

        detail = await self._call_tool(toolkit, "orch_get_proposal", {"proposal_id": proposal_id})
        self.assertIsInstance(detail, OrchestratorToolSuccess)
        self.assertEqual(detail.data["proposal_id"], proposal_id)
        self.assertEqual(detail.data["proposals"][0]["id"], "task-4")

        applied = await self._call_tool(
            toolkit,
            "orch_apply_proposal",
            {"proposal_id": proposal_id, "note": "Looks good."},
        )
        self.assertIsInstance(applied, OrchestratorToolSuccess)
        self.assertEqual(applied.data["status"], "applied")
        self.assertEqual(applied.data["applied_task_ids"], ["task-4"])
        self.assertEqual(manager.get_task("task-4").title, "Follow-up task")

        apply_again = await self._call_tool(toolkit, "orch_apply_proposal", {"proposal_id": proposal_id})
        self.assertIsInstance(apply_again, OrchestratorToolFailure)
        self.assertEqual(apply_again.error.kind, "proposal_conflict")

        rejected_listing = await self._call_tool(toolkit, "orch_list_proposals", {"status": None})
        self.assertIsInstance(rejected_listing, OrchestratorToolSuccess)
        self.assertEqual(rejected_listing.data["proposals"][0]["status"], "applied")

        manager_reject = build_mutation_manager()
        reject_id = await self._record_worker_proposal(manager_reject)
        reject_toolkit = OrchestratorToolkit(manager_reject)
        first_reject = await self._call_tool(
            reject_toolkit,
            "orch_reject_proposal",
            {"proposal_id": reject_id, "note": "Out of scope."},
        )
        self.assertIsInstance(first_reject, OrchestratorToolSuccess)
        self.assertEqual(first_reject.data["status"], "rejected")
        artifact_count = len(manager_reject.get_task("task-2").artifacts)

        second_reject = await self._call_tool(
            reject_toolkit,
            "orch_reject_proposal",
            {"proposal_id": reject_id, "note": "Still out of scope."},
        )
        self.assertIsInstance(second_reject, OrchestratorToolSuccess)
        self.assertEqual(second_reject.data["status"], "rejected")
        self.assertEqual(len(manager_reject.get_task("task-2").artifacts), artifact_count)

    async def test_dispatch_tools_record_completion_and_runner_failures(self) -> None:
        manager = build_mutation_manager()
        runner = FakeWorkerRunner()
        runner.results["task-2"] = TaskExecutionResult(
            status=TaskExecutionStatus.completed,
            summary="worker completed task-2",
            artifacts=[TaskArtifact(kind="output", value="proof")],
            metadata={"worker": "fake"},
        )
        toolkit = OrchestratorToolkit(manager, worker_runner=runner)

        dispatched = await self._call_tool(toolkit, "orch_dispatch_task", {"task_id": "task-2"})
        self.assertIsInstance(dispatched, OrchestratorToolSuccess)
        self.assertEqual(dispatched.data["execution_status"], "completed")
        self.assertEqual(dispatched.data["task"]["lifecycle_status"], "completed")
        self.assertEqual(manager.get_task("task-2").artifacts[-1].value, "proof")
        self.assertEqual(runner.calls[0], ("task-2", "running", "fake-runner"))

        failing_manager = build_mutation_manager()
        failing_runner = FakeWorkerRunner()
        failing_runner.results["task-2"] = RuntimeError("worker crashed")
        failing_toolkit = OrchestratorToolkit(failing_manager, worker_runner=failing_runner)

        failed_dispatch = await self._call_tool(failing_toolkit, "orch_dispatch_next_ready", {})
        self.assertIsInstance(failed_dispatch, OrchestratorToolFailure)
        self.assertEqual(failed_dispatch.error.kind, "worker_dispatch_failed")
        self.assertEqual(failing_manager.get_task("task-2").status, TaskLifecycleStatus.failed)


class ErrorMappingTests(unittest.TestCase):
    def test_failure_from_exception_maps_expected_error_kinds(self) -> None:
        self.assertEqual(
            failure_from_exception("orch_get_task", TaskNotFoundError("missing")).error.kind,
            "task_not_found",
        )
        self.assertEqual(
            failure_from_exception("orch_claim_task", TaskTransitionError("bad transition")).error.kind,
            "invalid_transition",
        )
        self.assertEqual(
            failure_from_exception("orch_add_task", TaskConflictError("duplicate task")).error.kind,
            "task_conflict",
        )
        self.assertEqual(
            failure_from_exception("orch_add_dependency", MissingDependencyError("missing dep")).error.kind,
            "missing_dependency",
        )
        self.assertEqual(
            failure_from_exception("orch_add_dependency", TaskCycleError("cycle")).error.kind,
            "cycle_detected",
        )
        self.assertEqual(
            failure_from_exception(
                "orch_get_proposal",
                OrchestratorToolkitExecutionError(kind="proposal_not_found", message="missing", retryable=True),
            ).error.kind,
            "proposal_not_found",
        )
        self.assertEqual(
            failure_from_exception("orch_dispatch_task", Exception("boom")).error.kind,
            "orchestrator_tool_internal_error",
        )


class RoleSeparationTests(unittest.IsolatedAsyncioTestCase):
    async def test_worker_and_orchestrator_toolkits_expose_distinct_authority_surfaces(self) -> None:
        worker_model = TestModel(call_tools=[], custom_output_text="ok")
        worker_agent = Agent(worker_model, toolsets=[TaskToolkit(build_mutation_manager(), current_task_id="task-2")])

        await worker_agent.run("hello")

        assert worker_model.last_model_request_parameters is not None
        worker_names = {tool.name for tool in worker_model.last_model_request_parameters.function_tools}
        self.assertIn("task_current", worker_names)
        self.assertNotIn("orch_claim_task", worker_names)

        orch_model = TestModel(call_tools=[], custom_output_text="ok")
        orch_agent = Agent(orch_model, toolsets=[OrchestratorToolkit(build_mutation_manager())])

        await orch_agent.run("hello")

        assert orch_model.last_model_request_parameters is not None
        orch_names = {tool.name for tool in orch_model.last_model_request_parameters.function_tools}
        self.assertIn("orch_claim_task", orch_names)
        self.assertNotIn("task_current", orch_names)


if __name__ == "__main__":
    unittest.main()
