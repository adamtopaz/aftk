from __future__ import annotations

import asyncio
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from pydantic import ValidationError
from pydantic_ai import Agent
from pydantic_ai.models.test import TestModel

from aftk.agents import (
    InitializationResult,
    InitializerDeps,
    OrchestratorDecision,
    OrchestratorDeps,
    ProjectContextTools,
    ToolkitQueryTools,
    WorkerDeps,
    WorkerOutcome,
    WorkerReport,
    WorkerTaskBrief,
    build_initializer_toolsets,
    build_orchestrator_toolsets,
    build_worker_toolsets,
)
from aftk.config import FrameworkConfig
from aftk.project import ProjectSnapshotService
from aftk.tasks import (
    ArtifactKind,
    ArtifactRef,
    Blocker,
    BlockerKind,
    Task,
    TaskDraft,
    TaskPatch,
    TaskPriority,
    TaskState,
    TaskStatus,
)
from aftk_client import HoverResult


def make_config(root: Path) -> FrameworkConfig:
    root.mkdir(parents=True, exist_ok=True)
    (root / "lakefile.toml").write_text('name = "demo"\n', encoding="utf-8")
    (root / "entrypoint.md").write_text("# Demo\nFormalize the project.\n", encoding="utf-8")
    return FrameworkConfig.from_project_root(root)


def make_snapshot(config: FrameworkConfig):
    return ProjectSnapshotService(config).build_snapshot(now=datetime(2026, 1, 1, tzinfo=timezone.utc))


def make_task(task_id: str = "task-0001") -> Task:
    timestamp = datetime(2026, 1, 1, tzinfo=timezone.utc)
    return Task(
        id=task_id,
        title="Prove demo theorem",
        description="Finish the first theorem in Demo.lean.",
        kind="formalization",
        status=TaskStatus.READY,
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


class EmptyToolkitClient:
    pass


class FakeToolkitClient:
    def __init__(self) -> None:
        self.calls: list[tuple[str, tuple[object, ...], dict[str, object]]] = []

    async def get_hover(self, path: str, line: int, col: int, *, timeout: float | None = None) -> HoverResult | None:
        self.calls.append(("get_hover", (path, line, col), {"timeout": timeout}))
        return HoverResult(text=f"hover:{path}:{line}:{col}")


class AgentModelTests(unittest.TestCase):
    def test_agent_models_validate_and_helpers_preserve_task_focus(self) -> None:
        task = make_task()
        brief = WorkerTaskBrief.from_task(
            task,
            local_context="Demo.lean lines 1-20",
            suggested_starting_points=["Inspect theorem demo", "Run lake build after edits"],
        )

        self.assertEqual(brief.task_id, task.id)
        self.assertEqual(brief.scope, task.scope)
        self.assertEqual(brief.suggested_starting_points[0], "Inspect theorem demo")

        init_result = InitializationResult(
            project_summary="Lean project with one unfinished theorem.",
            assumptions=["The imported mathlib dependencies build successfully."],
            risks=["The source notes may be incomplete."],
            initial_tasks=[
                TaskDraft(
                    title="Finish demo theorem",
                    description="Prove the remaining theorem in Demo.lean.",
                    kind="formalization",
                    acceptance_criteria=["lake build succeeds"],
                    scope=[ArtifactRef(kind=ArtifactKind.FILE, value="Demo.lean")],
                )
            ],
        )
        self.assertEqual(len(init_result.initial_tasks), 1)

        decision = OrchestratorDecision(
            project_done=False,
            selected_task_id=task.id,
            worker_brief=brief,
            task_patches=[TaskPatch(task_id=task.id, append_notes=["Prioritize this next."])],
            rationale="The task is ready and locally scoped.",
        )
        self.assertEqual(decision.worker_brief.task_id, task.id)

        report = WorkerReport(
            outcome=WorkerOutcome.COMPLETED,
            summary="Finished the proof and validated with lake build.",
            evidence=["`lake build` exited with code 0."],
            changed_artifacts=[ArtifactRef(kind=ArtifactKind.FILE, value="Demo.lean")],
        )
        self.assertEqual(report.outcome, WorkerOutcome.COMPLETED)

        with self.assertRaises(ValidationError):
            OrchestratorDecision(
                project_done=True,
                rationale="All required tasks are complete.",
            )
        with self.assertRaises(ValidationError):
            OrchestratorDecision(
                project_done=False,
                selected_task_id="task-0002",
                worker_brief=brief,
                rationale="Mismatched task selection.",
            )
        with self.assertRaises(ValidationError):
            WorkerReport(
                outcome=WorkerOutcome.BLOCKED,
                summary="Need additional information.",
            )

    def test_dependency_containers_are_typed_and_frozen(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            snapshot = make_snapshot(config)
            task_state = TaskState.empty(now=datetime(2026, 1, 1, tzinfo=timezone.utc))
            brief = WorkerTaskBrief.from_task(make_task())
            report = WorkerReport(
                outcome=WorkerOutcome.PARTIAL,
                summary="Made partial progress.",
            )
            client = EmptyToolkitClient()

            initializer_deps = InitializerDeps(config=config, project_snapshot=snapshot, toolkit_client=client)  # type: ignore[arg-type]
            orchestrator_deps = OrchestratorDeps(
                config=config,
                project_snapshot=snapshot,
                task_snapshot=task_state,
                toolkit_client=client,  # type: ignore[arg-type]
                last_worker_report=report,
            )
            worker_deps = WorkerDeps(
                config=config,
                project_snapshot=snapshot,
                task_brief=brief,
                toolkit_client=client,  # type: ignore[arg-type]
            )

            self.assertEqual(initializer_deps.project_snapshot.entrypoint_path, "entrypoint.md")
            self.assertEqual(orchestrator_deps.last_worker_report, report)
            self.assertEqual(worker_deps.task_brief.task_id, "task-0001")


class AgentToolTests(unittest.TestCase):
    def test_project_context_tools_read_snapshot_backed_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            (root / "Demo.lean").write_text("theorem demo : True := trivial\n", encoding="utf-8")
            (root / "sources").mkdir()
            (root / "sources" / "notes.md").write_text("Important notes\n", encoding="utf-8")
            snapshot = make_snapshot(config)

            tools = ProjectContextTools(snapshot)
            summary = tools.get_project_snapshot_summary()
            self.assertEqual(summary.entrypoint_path, "entrypoint.md")
            self.assertEqual(summary.source_file_count, 1)
            self.assertEqual(summary.lean_file_paths, ["Demo.lean"])
            self.assertEqual(tools.read_entrypoint().content, "# Demo\nFormalize the project.\n")
            self.assertEqual([entry.path for entry in tools.list_source_files()], ["sources/notes.md"])
            self.assertEqual(tools.read_source_file("sources/notes.md").content, "Important notes\n")
            self.assertEqual([entry.path for entry in tools.list_lean_files()], ["Demo.lean"])
            with self.assertRaises(ValueError):
                tools.read_source_file("Demo.lean")

    def test_toolkit_query_tools_delegate_to_underlying_client(self) -> None:
        client = FakeToolkitClient()
        tools = ToolkitQueryTools(client)  # type: ignore[arg-type]

        result = asyncio.run(tools.get_hover("Demo.lean", 3, 7, timeout_seconds=1.5))

        self.assertEqual(result.text, "hover:Demo.lean:3:7")
        self.assertEqual(client.calls, [("get_hover", ("Demo.lean", 3, 7), {"timeout": 1.5})])

    def test_role_scoped_toolsets_expose_read_only_tools_to_planners_and_coding_tools_to_workers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            (root / "Demo.lean").write_text("theorem demo : True := trivial\n", encoding="utf-8")
            (root / "sources").mkdir()
            (root / "sources" / "notes.md").write_text("Important notes\n", encoding="utf-8")
            snapshot = make_snapshot(config)
            toolkit_client = EmptyToolkitClient()

            initializer_names = self._tool_names(build_initializer_toolsets(snapshot, toolkit_client))
            orchestrator_names = self._tool_names(build_orchestrator_toolsets(snapshot, toolkit_client))
            worker_names = self._tool_names(build_worker_toolsets(config, snapshot, toolkit_client))

            self.assertEqual(initializer_names, orchestrator_names)
            for expected in {"get_project_snapshot_summary", "read_entrypoint", "knowledgebase_status", "run_tactic"}:
                self.assertIn(expected, initializer_names)
            self.assertNotIn("write_file", initializer_names)
            self.assertNotIn("lake_build", initializer_names)

            for expected in {
                "get_project_snapshot_summary",
                "knowledgebase_status",
                "run_tactic",
                "list_project_files",
                "search_project_text",
                "write_file",
                "replace_in_file",
                "lake_build",
            }:
                self.assertIn(expected, worker_names)

    @staticmethod
    def _tool_names(toolsets: tuple[object, ...]) -> set[str]:
        model = TestModel(custom_output_text="ok", call_tools=[])
        agent = Agent(model, toolsets=toolsets)
        agent.run_sync("List the tools available for this role.")
        assert model.last_model_request_parameters is not None
        return {tool.name for tool in model.last_model_request_parameters.function_tools}


if __name__ == "__main__":
    unittest.main()
