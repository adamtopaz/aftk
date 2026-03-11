from __future__ import annotations

import asyncio
import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from pydantic_ai.messages import ModelRequest, ModelResponse, TextPart
from pydantic_ai.models.function import AgentInfo, FunctionModel
from pydantic_ai.models.test import TestModel

from aftk.agents import (
    DEFAULT_INITIALIZER_USER_PROMPT,
    InitializationAlreadyExistsError,
    InitializerDeps,
    InitializerService,
    build_initializer_agent,
)
from aftk.config import FrameworkConfig
from aftk.project import ProjectSnapshotService


class EmptyToolkitClient:
    pass


def make_config(root: Path) -> FrameworkConfig:
    root.mkdir(parents=True, exist_ok=True)
    (root / "lakefile.toml").write_text('name = "demo"\n', encoding="utf-8")
    (root / "entrypoint.md").write_text("# Demo\nFormalize the project.\n", encoding="utf-8")
    return FrameworkConfig.from_project_root(root)


def make_snapshot(config: FrameworkConfig):
    return ProjectSnapshotService(config).build_snapshot(now=datetime(2026, 1, 1, tzinfo=timezone.utc))


class InitializerAgentTests(unittest.TestCase):
    def test_initializer_agent_includes_snapshot_context_and_read_only_toolsets(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            (root / "Demo.lean").write_text("theorem demo : True := trivial\n", encoding="utf-8")
            (root / "sources").mkdir()
            (root / "sources" / "notes.md").write_text("Important notes\n", encoding="utf-8")
            snapshot = make_snapshot(config)
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
                                    "project_summary": "Lean demo project with one theorem and one notes file.",
                                    "assumptions": ["The current Lean environment already builds."],
                                    "risks": ["The notes may omit proof details."],
                                    "initial_tasks": [
                                        {
                                            "title": "Inspect the demo theorem",
                                            "description": "Read Demo.lean and identify the current proof state.",
                                            "kind": "formalization",
                                            "acceptance_criteria": ["The target theorem and local context are documented."],
                                            "scope": [{"kind": "file", "value": "Demo.lean"}],
                                        }
                                    ],
                                }
                            )
                        )
                    ]
                )

            agent = build_initializer_agent(FunctionModel(model_function, model_name="function:initializer"))
            result = agent.run_sync(
                DEFAULT_INITIALIZER_USER_PROMPT,
                deps=InitializerDeps(
                    config=config,
                    project_snapshot=snapshot,
                    toolkit_client=EmptyToolkitClient(),  # type: ignore[arg-type]
                ),
            )

            instructions = captured["instructions"]
            tool_names = captured["tool_names"]
            assert isinstance(instructions, str)
            assert isinstance(tool_names, set)

            self.assertEqual(result.output.project_summary, "Lean demo project with one theorem and one notes file.")
            self.assertIn("Project root:", instructions)
            self.assertIn("Source files: sources/notes.md", instructions)
            self.assertIn("Lean files: Demo.lean", instructions)
            self.assertIn("TaskDraft.depends_on should normally be empty", instructions)
            self.assertIn("read_entrypoint", tool_names)
            self.assertIn("list_source_files", tool_names)
            self.assertIn("knowledgebase_status", tool_names)
            self.assertIn("run_tactic", tool_names)
            self.assertNotIn("write_file", tool_names)
            self.assertNotIn("lake_build", tool_names)


class InitializerServiceTests(unittest.TestCase):
    def test_initialize_persists_summary_and_seeds_tasks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            (root / "Demo.lean").write_text("theorem demo : True := trivial\n", encoding="utf-8")
            (root / "sources").mkdir()
            (root / "sources" / "notes.md").write_text("Important notes\n", encoding="utf-8")
            service = InitializerService(config)
            model = TestModel(
                call_tools=[],
                custom_output_args={
                    "project_summary": "Demo project with one Lean theorem and one notes file.",
                    "assumptions": ["Mathlib dependencies are already configured."],
                    "risks": ["The notes may not fully specify the proof."],
                    "initial_tasks": [
                        {
                            "title": "Read the notes",
                            "description": "Inspect sources/notes.md for the intended theorem statement.",
                            "kind": "knowledge_extraction",
                            "acceptance_criteria": ["The theorem statement is recorded in task notes or context."],
                            "scope": [{"kind": "source", "value": "sources/notes.md"}],
                        },
                        {
                            "title": "Inspect Demo.lean",
                            "description": "Review Demo.lean and identify the first unfinished proof obligation.",
                            "kind": "formalization",
                            "acceptance_criteria": ["The first unfinished goal is identified."],
                            "scope": [{"kind": "file", "value": "Demo.lean"}],
                        },
                    ],
                },
            )

            record = asyncio.run(service.initialize(EmptyToolkitClient(), model=model))  # type: ignore[arg-type]

            self.assertEqual(record.project_root, str(root.resolve()))
            self.assertEqual(record.snapshot_path, ".aftk/project/snapshot.json")
            self.assertEqual(record.result.project_summary, "Demo project with one Lean theorem and one notes file.")
            self.assertEqual(record.initial_task_ids, ["task-0001", "task-0002"])
            self.assertTrue((root / ".aftk" / "project" / "snapshot.json").is_file())
            self.assertTrue((root / ".aftk" / "project" / "initialization.json").is_file())
            self.assertEqual(service.load_initialization(), record)

            state = service.task_service.load_state()
            self.assertEqual(sorted(state.tasks), ["task-0001", "task-0002"])
            self.assertEqual(state.tasks["task-0001"].title, "Read the notes")
            self.assertEqual(state.tasks["task-0002"].scope[0].value, "Demo.lean")

    def test_initialize_rejects_reinitialization(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            (root / "Demo.lean").write_text("theorem demo : True := trivial\n", encoding="utf-8")
            service = InitializerService(config)
            model = TestModel(
                call_tools=[],
                custom_output_args={
                    "project_summary": "Already initialized demo project.",
                    "assumptions": [],
                    "risks": [],
                    "initial_tasks": [
                        {
                            "title": "Inspect Demo.lean",
                            "description": "Read the project file.",
                            "kind": "formalization",
                            "acceptance_criteria": ["The initial inspection is complete."],
                            "scope": [{"kind": "file", "value": "Demo.lean"}],
                        }
                    ],
                },
            )

            first = asyncio.run(service.initialize(EmptyToolkitClient(), model=model))  # type: ignore[arg-type]
            self.assertEqual(first.initial_task_ids, ["task-0001"])

            with self.assertRaises(InitializationAlreadyExistsError):
                asyncio.run(service.initialize(EmptyToolkitClient(), model=model))  # type: ignore[arg-type]


if __name__ == "__main__":
    unittest.main()
