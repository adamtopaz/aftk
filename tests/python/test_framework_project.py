from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from pydantic import ValidationError

from aftk.config import AgentModelSettings, FrameworkConfig, FrameworkConfigError
from aftk.project import ProjectSnapshotService


def ts(year: int, month: int, day: int, hour: int = 0, minute: int = 0, second: int = 0) -> datetime:
    return datetime(year, month, day, hour, minute, second, tzinfo=timezone.utc)


class FrameworkConfigTests(unittest.TestCase):
    def test_config_discovers_framework_paths_and_role_models(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "lakefile.toml").write_text('name = "demo"\n', encoding="utf-8")
            (root / "entrypoint.md").write_text("# Demo\nFormalize the project.\n", encoding="utf-8")

            config = FrameworkConfig.from_project_root(
                root,
                models=AgentModelSettings(
                    initializer="openai:gpt-5.2",
                    orchestrator="openrouter:google/gemini-3-pro-preview",
                    worker="anthropic:claude-sonnet-4-5",
                ),
            )

            self.assertEqual(config.project_root, root.resolve())
            self.assertEqual(config.paths.entrypoint_path, (root / "entrypoint.md").resolve())
            self.assertEqual(config.paths.state_dir, (root / ".aftk").resolve())
            self.assertEqual(config.paths.project_state_dir, (root / ".aftk" / "project").resolve())
            self.assertEqual(config.paths.tasks_dir, (root / ".aftk" / "tasks").resolve())
            self.assertEqual(config.paths.runs_dir, (root / ".aftk" / "runs").resolve())
            self.assertEqual(config.paths.relative_to_project_root(config.paths.project_state_dir), ".aftk/project")
            self.assertEqual(config.models.worker, "anthropic:claude-sonnet-4-5")

    def test_config_rejects_missing_entrypoint_and_paths_outside_project(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "lakefile.lean").write_text("import Lake\n", encoding="utf-8")

            with self.assertRaises(FrameworkConfigError):
                FrameworkConfig.from_project_root(root)

            (root / "entrypoint.md").write_text("# Demo\n", encoding="utf-8")
            with self.assertRaises(FrameworkConfigError):
                FrameworkConfig.from_project_root(root, state_dir="../outside")
            with self.assertRaises(FrameworkConfigError):
                FrameworkConfig.from_project_root(root, sources_dir=".")

    def test_role_model_names_follow_provider_model_format(self) -> None:
        with self.assertRaises(ValidationError):
            AgentModelSettings(initializer="gpt-5.2")

        settings = AgentModelSettings(worker="openai:gpt-5-mini")
        self.assertEqual(settings.worker, "openai:gpt-5-mini")


class ProjectSnapshotTests(unittest.TestCase):
    def test_snapshot_builds_deterministic_inventory_and_excludes_generated_dirs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "lakefile.toml").write_text('name = "demo"\n', encoding="utf-8")
            (root / "entrypoint.md").write_text("# Goal\nFormalize the demo.\n", encoding="utf-8")
            (root / "Demo.lean").write_text("def demo := 1\n", encoding="utf-8")
            (root / "Nested").mkdir()
            (root / "Nested" / "Support.lean").write_text("theorem support : True := trivial\n", encoding="utf-8")
            (root / "sources").mkdir()
            (root / "sources" / "notes.md").write_text("Notes\n", encoding="utf-8")
            (root / "sources" / "paper.pdf").write_bytes(b"%PDF-1.4\n")
            (root / ".aftk").mkdir()
            (root / ".aftk" / "Ignored.lean").write_text("def ignored := 0\n", encoding="utf-8")
            (root / ".lake" / "packages" / "Pkg").mkdir(parents=True)
            (root / ".lake" / "packages" / "Pkg" / "Pkg.lean").write_text(
                "def pkg := 0\n",
                encoding="utf-8",
            )

            service = ProjectSnapshotService(FrameworkConfig.from_project_root(root))
            snapshot = service.build_snapshot(now=ts(2026, 3, 1, 8))

            self.assertEqual(snapshot.project_root, str(root.resolve()))
            self.assertEqual(snapshot.generated_state_dir, ".aftk")
            self.assertEqual(snapshot.entrypoint_path, "entrypoint.md")
            self.assertEqual(snapshot.lakefile_path, "lakefile.toml")
            self.assertTrue(snapshot.sources_present)
            self.assertEqual([record.path for record in snapshot.source_inventory], ["sources/notes.md", "sources/paper.pdf"])
            self.assertEqual([record.path for record in snapshot.lean_files], ["Demo.lean", "Nested/Support.lean"])
            self.assertTrue(all(len(record.sha256) == 64 for record in snapshot.source_inventory))
            self.assertTrue(all(len(record.sha256) == 64 for record in snapshot.lean_files))

    def test_snapshot_persists_under_framework_project_and_handles_missing_sources(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "lakefile.lean").write_text("import Lake\n", encoding="utf-8")
            (root / "entrypoint.md").write_text("# Demo\n", encoding="utf-8")
            (root / "Demo.lean").write_text("def demo := 1\n", encoding="utf-8")

            service = ProjectSnapshotService(FrameworkConfig.from_project_root(root))
            snapshot = service.build_and_save_snapshot(now=ts(2026, 3, 1, 9))
            loaded = service.load_snapshot()

            self.assertEqual(loaded, snapshot)
            self.assertFalse(loaded.sources_present)
            self.assertEqual(loaded.source_inventory, [])
            self.assertTrue(service.store.snapshot_path.is_file())
            self.assertEqual(service.store.snapshot_path, (root / ".aftk" / "project" / "snapshot.json").resolve())
            self.assertIn('"entrypoint_path": "entrypoint.md"', service.store.snapshot_path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
