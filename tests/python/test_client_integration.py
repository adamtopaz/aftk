from __future__ import annotations

import asyncio
import unittest
from pathlib import Path

from pydantic import ValidationError

from aftk_client import AsyncAftkClient
from aftk_client.errors import DomainNotFoundError, FileNotOpenError


REPO_ROOT = Path(__file__).resolve().parents[2]
SEMANTICS_PATH = REPO_ROOT / "tests" / "server" / "fixtures" / "lean" / "Semantics.lean"
SEMANTICS_RELATIVE_PATH = Path("tests/server/fixtures/lean/Semantics.lean")
HOVER_LINE = 10
HOVER_COL = 26
TERM_GOAL_LINE = 13
TERM_GOAL_COL = 3
TACTIC_LINE = 16
TACTIC_COL = 3
KB_ROOT = REPO_ROOT / "tests" / "server" / "fixtures" / "knowledgebase" / "basic-valid"
LONG_BODY_ROOT = REPO_ROOT / "tests" / "informal" / "knowledgebase-fixtures" / "long-body"
INFORMAL_MODULES = ["AFTKTest.Informal.Fixtures.Basic"]


class ClientIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def test_open_query_and_tactic_flow(self) -> None:
        async with AsyncAftkClient(project_root=REPO_ROOT) as client:
            opened = await client.open(SEMANTICS_RELATIVE_PATH)
            self.assertTrue(opened.opened)

            hover = await client.get_hover(opened.path, HOVER_LINE, HOVER_COL)
            self.assertIsNotNone(hover)
            assert hover is not None
            self.assertIn("Nat.succ", hover.text)

            term_goal = await client.get_plain_term_goal(opened.path, TERM_GOAL_LINE, TERM_GOAL_COL)
            self.assertIsNotNone(term_goal)
            assert term_goal is not None
            self.assertIn("⊢ Nat", term_goal.goal)

            loaded = await client.load_node(opened.path, TACTIC_LINE, TACTIC_COL)
            self.assertEqual(len(loaded.ids), 1)
            node_id = loaded.ids[0]

            goals = await client.get_goals(opened.path, node_id)
            self.assertEqual(len(goals.goals), 1)
            self.assertIn("⊢ n + 0 = n", goals.goals[0])

            tactic_result = await client.run_tactic(opened.path, node_id, "simpa")
            self.assertEqual(tactic_result.goals, [])
            self.assertTrue(tactic_result.next_id.startswith("node-"))

            closed = await client.close(opened.path)
            self.assertTrue(closed.closed)

            with self.assertRaises(FileNotOpenError):
                await client.get_hover(opened.path, HOVER_LINE, HOVER_COL)

    async def test_auto_detect_project_root_from_file(self) -> None:
        client = AsyncAftkClient()
        try:
            opened = await client.open(SEMANTICS_PATH)
            self.assertEqual(client.project_root, REPO_ROOT)
            self.assertTrue(opened.path.endswith("Semantics.lean"))
        finally:
            await client.aclose()

    async def test_concurrent_queries(self) -> None:
        async with AsyncAftkClient(project_root=REPO_ROOT) as client:
            opened = await client.open(SEMANTICS_PATH)
            hover_task = client.get_hover(opened.path, HOVER_LINE, HOVER_COL)
            term_goal_task = client.get_plain_term_goal(opened.path, TERM_GOAL_LINE, TERM_GOAL_COL)
            hover, term_goal = await asyncio.gather(hover_task, term_goal_task)

            self.assertIsNotNone(hover)
            self.assertIsNotNone(term_goal)
            assert hover is not None
            assert term_goal is not None
            self.assertIn("Nat.succ", hover.text)
            self.assertIn("⊢ Nat", term_goal.goal)

    async def test_knowledgebase_methods(self) -> None:
        async with AsyncAftkClient(project_root=REPO_ROOT) as client:
            status = await client.knowledgebase_status(root=KB_ROOT)
            self.assertTrue(status.initialized)
            self.assertEqual(status.node_count, 1)

            listed = await client.knowledgebase_list(root=KB_ROOT, prefix="group.basic")
            self.assertEqual(len(listed.nodes), 1)
            self.assertEqual(listed.nodes[0].id, "group.basic.definition")

            shown = await client.knowledgebase_show("group.basic.definition", root=KB_ROOT)
            self.assertEqual(shown.node.metadata.title, "Definition of group")

            body = await client.knowledgebase_get_body("group.basic.definition", root=KB_ROOT)
            self.assertIn("inverse", body.body)

            metadata = await client.knowledgebase_get_metadata("group.basic.definition", root=KB_ROOT)
            self.assertEqual(metadata.status, "active")

            paths = await client.knowledgebase_get_paths("group.basic.definition", root=KB_ROOT)
            self.assertTrue(paths.paths.metadata_path.endswith("group/basic/definition.json"))

            search = await client.knowledgebase_search_text("inverse", root=KB_ROOT)
            self.assertEqual(len(search.hits), 1)
            self.assertEqual(search.hits[0].id, "group.basic.definition")

            validation = await client.knowledgebase_validate_all(root=KB_ROOT)
            self.assertTrue(validation.ok)

            with self.assertRaises(DomainNotFoundError):
                await client.knowledgebase_show("group.basic.missing", root=KB_ROOT)

    async def test_knowledgebase_write_methods(self) -> None:
        async with AsyncAftkClient(project_root=REPO_ROOT) as client:
            with self.subTest("init/create/update/rename/delete"):
                from tempfile import TemporaryDirectory

                with TemporaryDirectory() as tmp:
                    root = Path(tmp) / "knowledgebase"
                    initialized = await client.knowledgebase_init(root=root)
                    self.assertTrue(initialized.root_dir.endswith("knowledgebase"))

                    created = await client.knowledgebase_create(
                        "analysis.uniform_continuity",
                        title="Uniform continuity",
                        root=root,
                        kind="definition",
                        body="A uniformly continuous function preserves nearby points.\n",
                    )
                    self.assertEqual(created.node.metadata.title, "Uniform continuity")

                    updated_body = await client.knowledgebase_set_body(
                        "analysis.uniform_continuity",
                        "Updated body text\n",
                        root=root,
                    )
                    self.assertIn("Updated body text", updated_body.node.body)

                    replaced = await client.knowledgebase_replace_metadata(
                        "analysis.uniform_continuity",
                        {
                            "schemaVersion": 1,
                            "id": "analysis.uniform_continuity",
                            "title": "Uniform continuity (updated)",
                            "kind": "definition",
                            "status": "active",
                            "summary": "Updated summary",
                            "tags": ["analysis"],
                        },
                        root=root,
                    )
                    self.assertEqual(replaced.node.metadata.summary, "Updated summary")

                    renamed = await client.knowledgebase_rename(
                        "analysis.uniform_continuity",
                        "analysis.uniform_continuity.updated",
                        root=root,
                    )
                    self.assertEqual(renamed.stored.node.metadata.id, "analysis.uniform_continuity.updated")

                    deleted = await client.knowledgebase_delete(
                        "analysis.uniform_continuity.updated",
                        root=root,
                    )
                    self.assertTrue(deleted.deleted)

    async def test_informal_methods(self) -> None:
        async with AsyncAftkClient(project_root=REPO_ROOT) as client:
            status = await client.informal_status(INFORMAL_MODULES)
            self.assertEqual(status.tracked_declarations, 8)
            self.assertEqual(status.tracked_references, 5)

            decls = await client.informal_decls(INFORMAL_MODULES, ref="group.basic.definition")
            self.assertGreaterEqual(len(decls.entries), 1)

            decl = await client.informal_decl(INFORMAL_MODULES, "AFTKTest.Informal.Fixtures.Basic.multiRef")
            self.assertEqual(decl.entry.ref_count, 2)

            refs = await client.informal_refs(INFORMAL_MODULES, prefix="group.basic")
            self.assertTrue(any(entry.ref == "group.basic.definition" for entry in refs.entries))

            ref = await client.informal_ref(INFORMAL_MODULES, "group.basic.definition")
            self.assertGreater(ref.entry.decl_count, 0)

            decl_deps = await client.informal_decl_deps(INFORMAL_MODULES)
            self.assertGreater(len(decl_deps.rows), 0)

            ref_deps = await client.informal_ref_deps(INFORMAL_MODULES)
            self.assertGreater(len(ref_deps.rows), 0)

            present = await client.informal_present(
                "analysis.uniform_continuity",
                root=LONG_BODY_ROOT,
                mode="rich",
                body_mode="preview",
            )
            self.assertEqual(present.mode, "rich")
            self.assertIsNotNone(present.payload)
            assert present.payload is not None
            self.assertEqual(present.payload.body.kind, "preview")

            with self.assertRaises(DomainNotFoundError):
                await client.informal_decl(INFORMAL_MODULES, "AFTKTest.Informal.Fixtures.Basic.missing")

            with self.assertRaises(ValidationError):
                await client.informal_status([])

    async def test_client_side_position_validation(self) -> None:
        async with AsyncAftkClient(project_root=REPO_ROOT) as client:
            await client.open(SEMANTICS_PATH)
            with self.assertRaises(ValidationError):
                await client.get_hover(SEMANTICS_PATH, 0, 1)


if __name__ == "__main__":
    unittest.main()
