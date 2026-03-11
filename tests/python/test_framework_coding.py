from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import aftk.agents.tools.coding as worker_coding_module
from aftk.agents.tools import WorkerCodingTools, build_worker_coding_toolset
from aftk.coding import (
    CodingActionKind,
    CodingActionRecorder,
    CodingPermissionError,
    CodingSandboxError,
    EditConflictError,
    ProjectCommandService,
    ProjectFileService,
    ProjectSearchService,
)
from aftk.config import FrameworkConfig


def make_config(root: Path) -> FrameworkConfig:
    root.mkdir(parents=True, exist_ok=True)
    (root / "lakefile.toml").write_text('name = "demo"\n', encoding="utf-8")
    (root / "entrypoint.md").write_text("# Demo\n", encoding="utf-8")
    return FrameworkConfig.from_project_root(root)


class CodingFilesystemTests(unittest.TestCase):
    def test_file_reads_writes_and_edits_are_sandboxed_and_logged(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            recorder = CodingActionRecorder.for_project(
                config,
                run_id="run-0001",
                task_id="task-0001",
                attempt_id="attempt-0001",
            )
            files = ProjectFileService(config, recorder=recorder)

            write_result = files.write_file("Scratch.lean", "def demo := 1\n")
            self.assertTrue(write_result.created)
            self.assertFalse(write_result.overwritten)

            read_result = files.read_file("Scratch.lean")
            self.assertEqual(read_result.content, "def demo := 1\n")

            slice_result = files.read_file_slice("Scratch.lean", 1, 1)
            self.assertEqual(slice_result.content, "def demo := 1\n")
            self.assertEqual((slice_result.start_line, slice_result.end_line), (1, 1))

            replace_result = files.replace_in_file("Scratch.lean", "1", "2")
            self.assertTrue(replace_result.changed)
            self.assertEqual(replace_result.replacement_count, 1)

            append_result = files.append_to_file("Scratch.lean", "#check demo\n")
            self.assertTrue(append_result.changed)
            self.assertEqual((root / "Scratch.lean").read_text(encoding="utf-8"), "def demo := 2\n#check demo\n")

            with self.assertRaises(CodingSandboxError):
                files.write_file("../Escape.lean", "def escape := 0\n")

            with self.assertRaises(CodingPermissionError):
                files.write_file(".aftk/state.json", "{}", overwrite=True)

            self.assertEqual(
                recorder.store.path,
                (root / ".aftk" / "runs" / "run-0001" / "coding-actions.jsonl").resolve(),
            )
            actions = recorder.store.load_actions()
            self.assertEqual(
                [action.kind for action in actions],
                [
                    CodingActionKind.WRITE_FILE,
                    CodingActionKind.READ_FILE,
                    CodingActionKind.READ_FILE_SLICE,
                    CodingActionKind.REPLACE_IN_FILE,
                    CodingActionKind.APPEND_TO_FILE,
                ],
            )
            self.assertTrue(all(action.run_id == "run-0001" for action in actions))
            self.assertTrue(all(action.task_id == "task-0001" for action in actions))
            self.assertTrue(all(action.attempt_id == "attempt-0001" for action in actions))

    def test_symlink_escape_and_replace_conflicts_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            root = workspace / "project"
            outside = workspace / "outside"
            outside.mkdir()
            config = make_config(root)
            files = ProjectFileService(config)

            (outside / "Secret.lean").write_text("def secret := 7\n", encoding="utf-8")
            (root / "OutsideLink").symlink_to(outside, target_is_directory=True)
            with self.assertRaises(CodingSandboxError):
                files.read_file("OutsideLink/Secret.lean")

            (root / "Demo.lean").write_text("theorem demo : True := trivial\n", encoding="utf-8")
            with self.assertRaises(EditConflictError):
                files.replace_in_file("Demo.lean", "missing", "replacement")

            (root / "Repeated.lean").write_text("def x := 1\ndef y := 1\n", encoding="utf-8")
            with self.assertRaises(EditConflictError):
                files.replace_in_file("Repeated.lean", "1", "2")


class CodingSearchTests(unittest.TestCase):
    def test_search_lists_user_files_and_skips_generated_dirs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            recorder = CodingActionRecorder.for_project(config, run_id="run-0002")
            search = ProjectSearchService(config, recorder=recorder)

            (root / "Demo.lean").write_text("def demo := 1\n", encoding="utf-8")
            (root / "Nested").mkdir()
            (root / "Nested" / "Support.lean").write_text(
                "theorem support : True := trivial\n",
                encoding="utf-8",
            )
            (root / ".aftk").mkdir()
            (root / ".aftk" / "Ignored.lean").write_text("def ignored := 0\n", encoding="utf-8")
            (root / ".lake" / "packages" / "Pkg").mkdir(parents=True)
            (root / ".lake" / "packages" / "Pkg" / "Pkg.lean").write_text(
                "def pkg := 0\n",
                encoding="utf-8",
            )
            (root / "binary.dat").write_bytes(b"\x00\x01\x02")

            listed = [entry.path for entry in search.list_project_files(limit=20)]
            self.assertIn("Demo.lean", listed)
            self.assertIn("Nested/Support.lean", listed)
            self.assertIn("entrypoint.md", listed)
            self.assertNotIn(".aftk/Ignored.lean", listed)
            self.assertNotIn(".lake/packages/Pkg/Pkg.lean", listed)

            matches = search.search_project_text("support", include_globs=["*.lean"], limit=10)
            self.assertEqual([(match.path, match.line) for match in matches], [("Nested/Support.lean", 1)])

            actions = recorder.store.load_actions()
            self.assertEqual([action.kind for action in actions], [CodingActionKind.LIST_PROJECT_FILES, CodingActionKind.SEARCH_PROJECT_TEXT])
            self.assertEqual(actions[-1].details["result_count"], 1)


class CodingCommandTests(unittest.TestCase):
    def test_run_command_respects_cwd_and_logs_actions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            recorder = CodingActionRecorder.for_project(config, run_id="run-0003")
            commands = ProjectCommandService(config, recorder=recorder)

            (root / "Nested").mkdir()
            result = commands.run_command(["sh", "-c", "pwd"], cwd="Nested")

            self.assertEqual(result.exit_code, 0)
            self.assertFalse(result.timed_out)
            self.assertEqual(result.cwd, "Nested")
            self.assertEqual(result.stdout.strip(), str((root / "Nested").resolve()))

            with self.assertRaises(CodingPermissionError):
                commands.run_command(["sh", "-c", "pwd"], cwd=".aftk")

            actions = recorder.store.load_actions()
            self.assertEqual([action.kind for action in actions], [CodingActionKind.RUN_COMMAND])
            self.assertEqual(actions[0].argv, ["sh", "-c", "pwd"])
            self.assertEqual(actions[0].details["cwd"], "Nested")

    def test_lake_build_timeout_and_worker_tool_wrapper(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            recorder = CodingActionRecorder.for_project(config, run_id="run-0004")
            commands = ProjectCommandService(config, recorder=recorder)

            timeout = subprocess.TimeoutExpired(
                cmd=["lake", "build", "Demo"],
                timeout=0.1,
                output=b"partial stdout",
                stderr=b"partial stderr",
            )
            with patch("aftk.coding.commands.subprocess.run", side_effect=timeout):
                result = commands.lake_build(target="Demo", timeout_seconds=0.1)

            self.assertEqual(result.argv, ["lake", "build", "Demo"])
            self.assertTrue(result.timed_out)
            self.assertEqual(result.exit_code, -1)
            self.assertEqual(result.stdout, "partial stdout")
            self.assertEqual(result.stderr, "partial stderr")

            actions = recorder.store.load_actions()
            self.assertEqual([action.kind for action in actions], [CodingActionKind.LAKE_BUILD])
            self.assertEqual(actions[0].argv, ["lake", "build", "Demo"])

            tools = WorkerCodingTools(config, recorder=recorder)
            self.assertEqual(
                [tool.__name__ for tool in tools.tool_functions()],
                [
                    "list_project_files",
                    "search_project_text",
                    "read_file",
                    "read_file_slice",
                    "write_file",
                    "replace_in_file",
                    "append_to_file",
                    "run_command",
                    "lake_build",
                ],
            )

            if worker_coding_module.FunctionToolset is None:
                with self.assertRaises(RuntimeError):
                    build_worker_coding_toolset(config, recorder=recorder)
            else:
                self.assertIsNotNone(build_worker_coding_toolset(config, recorder=recorder))


if __name__ == "__main__":
    unittest.main()
