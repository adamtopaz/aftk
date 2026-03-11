from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from aftk_client.client import AsyncAftkClient, detect_project_root, is_lake_project_root, validate_project_root
from aftk_client.errors import InvalidProjectRootError, ProjectRootNotFoundError


class ProjectRootTests(unittest.TestCase):
    def test_detect_project_root_from_nested_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "lakefile.lean").write_text("import Lake\n", encoding="utf-8")
            nested = root / "A" / "B" / "C"
            nested.mkdir(parents=True)
            target = nested / "Test.lean"
            target.write_text("def x := 1\n", encoding="utf-8")

            detected = detect_project_root(target)
            self.assertEqual(detected, root.resolve())
            self.assertTrue(is_lake_project_root(detected))

    def test_validate_project_root_rejects_non_lake_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(InvalidProjectRootError):
                validate_project_root(tmp)

    def test_detect_project_root_errors_when_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "Test.lean"
            target.write_text("def x := 1\n", encoding="utf-8")
            with self.assertRaises(ProjectRootNotFoundError):
                detect_project_root(target)

    def test_for_file_sets_project_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "lakefile.toml").write_text("name = \"demo\"\n", encoding="utf-8")
            target = root / "Demo.lean"
            target.write_text("def demo := 1\n", encoding="utf-8")

            client = AsyncAftkClient.for_file(target)
            self.assertEqual(client.project_root, root.resolve())


if __name__ == "__main__":
    unittest.main()
