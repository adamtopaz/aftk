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
from aftk.errors import DomainNotFoundError
from aftk.models import HoverResult, LoadNodeResult, NodeMetadata, OpenResult, RunTacticResult, StoredNode
from aftk.toolkits.aftk import AftkToolFailure, AftkToolSuccess, AftkToolkit


REPO_ROOT = Path(__file__).resolve().parents[2]
SEMANTICS_PATH = Path("tests/server/fixtures/lean/Semantics.lean")
HOVER_LINE = 10
HOVER_COL = 26
TACTIC_LINE = 16
TACTIC_COL = 3
KB_ROOT = REPO_ROOT / "tests" / "server" / "fixtures" / "knowledgebase" / "basic-valid"
LONG_BODY_ROOT = REPO_ROOT / "tests" / "informal" / "knowledgebase-fixtures" / "long-body"
INFORMAL_MODULES = ["AFTKTest.Informal.Fixtures.Basic"]


class FakeClient:
    def __init__(self) -> None:
        self.calls: list[tuple[str, tuple[Any, ...], dict[str, Any]]] = []
        self.close_count = 0
        self.load_node_result = LoadNodeResult.model_validate({"id": ["node-1"]})
        self.hover_result = HoverResult(text="Nat.succ")
        self.run_tactic_result = RunTacticResult.model_validate({"goals": [], "nextId": "node-2"})
        self.metadata_result = NodeMetadata.model_validate(
            {
                "schemaVersion": 1,
                "id": "group.basic.definition",
                "title": "Definition of group",
                "kind": "definition",
                "status": "active",
                "summary": "Original summary",
                "tags": ["algebra"],
                "authors": ["tester"],
            }
        )
        self.replace_metadata_result = StoredNode.model_validate(
            {
                "node": {
                    "metadata": {
                        "schemaVersion": 1,
                        "id": "group.basic.definition",
                        "title": "Updated title",
                        "kind": "definition",
                        "status": "active",
                        "summary": "Updated summary",
                        "tags": ["group"],
                        "authors": ["agent"],
                    },
                    "body": "Body text\n",
                },
                "paths": {
                    "markdownPath": "group/basic/definition.md",
                    "metadataPath": "group/basic/definition.json",
                },
            }
        )

    async def aclose(self) -> None:
        self.close_count += 1

    async def open(self, path: str) -> OpenResult:
        self.calls.append(("open", (path,), {}))
        return OpenResult(path=path, opened=True)

    async def get_hover(self, path: str, line: int, col: int) -> HoverResult:
        self.calls.append(("get_hover", (path, line, col), {}))
        return self.hover_result

    async def load_node(self, path: str, line: int, col: int) -> LoadNodeResult:
        self.calls.append(("load_node", (path, line, col), {}))
        return self.load_node_result

    async def run_tactic(self, path: str, node_id: str, tactic: str) -> RunTacticResult:
        self.calls.append(("run_tactic", (path, node_id, tactic), {}))
        return self.run_tactic_result

    async def knowledgebase_show(self, node_id: str, *, root: str | None = None) -> StoredNode:
        self.calls.append(("knowledgebase_show", (node_id,), {"root": root}))
        raise DomainNotFoundError(
            code=-32020,
            message="domain not found",
            data={
                "layer": "knowledgebase",
                "code": "node_not_found",
                "message": "Node not found",
                "exitCode": 2,
            },
            method="knowledgebase_show",
            request_id=7,
        )

    async def knowledgebase_get_metadata(self, node_id: str, *, root: str | None = None) -> NodeMetadata:
        self.calls.append(("knowledgebase_get_metadata", (node_id,), {"root": root}))
        return self.metadata_result

    async def knowledgebase_replace_metadata(
        self,
        node_id: str,
        metadata: NodeMetadata | dict[str, Any],
        *,
        root: str | None = None,
    ) -> StoredNode:
        self.calls.append(("knowledgebase_replace_metadata", (node_id, metadata), {"root": root}))
        return self.replace_metadata_result


class ToolkitSchemaTests(unittest.IsolatedAsyncioTestCase):
    async def test_agent_exposes_expected_basic_tools(self) -> None:
        model = TestModel(call_tools=[], custom_output_text="ok")
        toolkit = AftkToolkit(cast(AsyncAftkClient, FakeClient()))
        agent = Agent(model, toolsets=[toolkit])

        result = await agent.run("hello")

        self.assertEqual(result.output, "ok")
        assert model.last_model_request_parameters is not None
        tool_defs = {tool.name: tool for tool in model.last_model_request_parameters.function_tools}

        self.assertIn("lean_get_hover", tool_defs)
        self.assertIn("kb_status", tool_defs)
        self.assertIn("informal_present", tool_defs)
        self.assertNotIn("lean_open_file", tool_defs)
        self.assertNotIn("kb_replace_metadata_raw", tool_defs)

        hover_tool = tool_defs["lean_get_hover"]
        self.assertTrue(hover_tool.sequential)
        self.assertEqual(hover_tool.metadata, {"source": "aftk", "layer": "lean", "mutates": False, "advanced": False})
        self.assertEqual(
            hover_tool.parameters_json_schema["properties"]["path"]["description"],
            "Path to a Lean source file. Relative paths are resolved against the client's configured project root when one is available.",
        )
        self.assertEqual(hover_tool.parameters_json_schema["properties"]["line"]["minimum"], 1)

    async def test_advanced_and_read_only_flags_filter_tools(self) -> None:
        model = TestModel(call_tools=[], custom_output_text="ok")
        toolkit = AftkToolkit(cast(AsyncAftkClient, FakeClient()), advanced=True, read_only=True)
        agent = Agent(model, toolsets=[toolkit])

        await agent.run("hello")

        assert model.last_model_request_parameters is not None
        names = {tool.name for tool in model.last_model_request_parameters.function_tools}

        self.assertIn("lean_open_file", names)
        self.assertIn("kb_get_metadata", names)
        self.assertIn("kb_validate_storage", names)
        self.assertNotIn("kb_create_node", names)
        self.assertNotIn("kb_init", names)
        self.assertNotIn("kb_replace_metadata_raw", names)


class ToolkitBehaviorTests(unittest.IsolatedAsyncioTestCase):
    def _context(self) -> RunContext[Any]:
        return RunContext(deps=None, model=TestModel(call_tools=[]), usage=RunUsage())

    async def _call_tool(self, toolkit: AftkToolkit, name: str, args: dict[str, Any]) -> Any:
        ctx = self._context()
        tools = await toolkit.get_tools(ctx)
        tool = tools[name]
        validated_args = tool.args_validator.validate_python(args)
        return await toolkit.call_tool(name, validated_args, ctx, tool)

    async def test_basic_lean_query_auto_opens_file(self) -> None:
        client = FakeClient()
        toolkit = AftkToolkit(cast(AsyncAftkClient, client))

        result = await self._call_tool(
            toolkit,
            "lean_get_hover",
            {"path": "Tests.lean", "line": HOVER_LINE, "col": HOVER_COL},
        )

        self.assertIsInstance(result, AftkToolSuccess)
        self.assertEqual(result.data["text"], "Nat.succ")
        self.assertEqual(
            client.calls,
            [
                ("open", ("Tests.lean",), {}),
                ("get_hover", ("Tests.lean", HOVER_LINE, HOVER_COL), {}),
            ],
        )

    async def test_load_node_without_single_result_returns_failure(self) -> None:
        client = FakeClient()
        client.load_node_result = LoadNodeResult.model_validate({"id": []})
        toolkit = AftkToolkit(cast(AsyncAftkClient, client))

        result = await self._call_tool(
            toolkit,
            "lean_run_tactic_at",
            {"path": "Tests.lean", "line": TACTIC_LINE, "col": TACTIC_COL, "tactic": "simpa"},
        )

        self.assertIsInstance(result, AftkToolFailure)
        self.assertEqual(result.error.kind, "no_node_at_position")
        self.assertTrue(result.error.retryable)
        self.assertEqual(result.error.suggested_action, "choose_different_position")

    async def test_domain_errors_are_wrapped_in_failure_envelope(self) -> None:
        client = FakeClient()
        toolkit = AftkToolkit(cast(AsyncAftkClient, client))

        result = await self._call_tool(
            toolkit,
            "kb_show_node",
            {"node_id": "group.basic.missing", "root": str(KB_ROOT)},
        )

        self.assertIsInstance(result, AftkToolFailure)
        self.assertEqual(result.error.kind, "domain_not_found")
        self.assertFalse(result.error.retryable)
        self.assertEqual(result.error.details["domain_code"], "node_not_found")
        self.assertEqual(result.error.details["method"], "knowledgebase_show")

    async def test_patch_metadata_reads_then_replaces(self) -> None:
        client = FakeClient()
        toolkit = AftkToolkit(cast(AsyncAftkClient, client))

        result = await self._call_tool(
            toolkit,
            "kb_patch_metadata",
            {
                "node_id": "group.basic.definition",
                "root": str(KB_ROOT),
                "title": "Updated title",
                "summary": "Updated summary",
                "tags": ["group"],
                "authors": ["agent"],
            },
        )

        self.assertIsInstance(result, AftkToolSuccess)
        self.assertEqual(result.data["node"]["metadata"]["title"], "Updated title")
        self.assertEqual(client.calls[0][0], "knowledgebase_get_metadata")
        self.assertEqual(client.calls[1][0], "knowledgebase_replace_metadata")
        replaced_metadata = client.calls[1][1][1]
        assert isinstance(replaced_metadata, NodeMetadata)
        self.assertEqual(replaced_metadata.title, "Updated title")
        self.assertEqual(replaced_metadata.summary, "Updated summary")
        self.assertEqual(replaced_metadata.tags, ["group"])
        self.assertEqual(replaced_metadata.authors, ["agent"])

    async def test_toolkit_can_optionally_close_the_injected_client(self) -> None:
        client = FakeClient()
        toolkit = AftkToolkit(cast(AsyncAftkClient, client), close_client_on_exit=True)

        async with toolkit:
            pass

        self.assertEqual(client.close_count, 1)


class ToolkitIntegrationTests(unittest.IsolatedAsyncioTestCase):
    def _context(self) -> RunContext[Any]:
        return RunContext(deps=None, model=TestModel(call_tools=[]), usage=RunUsage())

    async def _call_tool(self, toolkit: AftkToolkit, name: str, args: dict[str, Any]) -> Any:
        ctx = self._context()
        tools = await toolkit.get_tools(ctx)
        tool = tools[name]
        validated_args = tool.args_validator.validate_python(args)
        return await toolkit.call_tool(name, validated_args, ctx, tool)

    async def test_real_client_basic_lean_tools(self) -> None:
        async with AsyncAftkClient(project_root=REPO_ROOT) as client:
            toolkit = AftkToolkit(client)

            hover = await self._call_tool(
                toolkit,
                "lean_get_hover",
                {"path": str(SEMANTICS_PATH), "line": HOVER_LINE, "col": HOVER_COL},
            )
            tactic = await self._call_tool(
                toolkit,
                "lean_run_tactic_at",
                {"path": str(SEMANTICS_PATH), "line": TACTIC_LINE, "col": TACTIC_COL, "tactic": "simpa"},
            )

            self.assertIsInstance(hover, AftkToolSuccess)
            self.assertIn("Nat.succ", hover.data["text"])
            self.assertIsInstance(tactic, AftkToolSuccess)
            self.assertEqual(tactic.data["goals"], [])
            self.assertTrue(tactic.data["next_id"].startswith("node-"))

    async def test_real_client_basic_knowledgebase_and_informal_tools(self) -> None:
        async with AsyncAftkClient(project_root=REPO_ROOT) as client:
            toolkit = AftkToolkit(client)

            status = await self._call_tool(toolkit, "kb_status", {"root": str(KB_ROOT)})
            present = await self._call_tool(
                toolkit,
                "informal_present",
                {
                    "ref": "analysis.uniform_continuity",
                    "root": str(LONG_BODY_ROOT),
                    "mode": "rich",
                    "body_mode": "preview",
                },
            )

            self.assertIsInstance(status, AftkToolSuccess)
            self.assertTrue(status.data["initialized"])
            self.assertEqual(status.data["node_count"], 1)
            self.assertIsInstance(present, AftkToolSuccess)
            self.assertEqual(present.data["mode"], "rich")
            self.assertEqual(present.data["payload"]["body"]["kind"], "preview")

    async def test_real_client_failures_are_returned_to_agent(self) -> None:
        async with AsyncAftkClient(project_root=REPO_ROOT) as client:
            toolkit = AftkToolkit(client)

            result = await self._call_tool(
                toolkit,
                "kb_show_node",
                {"node_id": "group.basic.missing", "root": str(KB_ROOT)},
            )

            self.assertIsInstance(result, AftkToolFailure)
            self.assertEqual(result.error.kind, "domain_not_found")
            self.assertEqual(result.error.details["domain_layer"], "knowledgebase")

    async def test_real_client_write_tools_work_against_temporary_root(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp) / "knowledgebase"
            async with AsyncAftkClient(project_root=REPO_ROOT) as client:
                toolkit = AftkToolkit(client, advanced=True)

                initialized = await self._call_tool(toolkit, "kb_init", {"root": str(root)})
                created = await self._call_tool(
                    toolkit,
                    "kb_create_node",
                    {
                        "root": str(root),
                        "node_id": "analysis.uniform_continuity",
                        "title": "Uniform continuity",
                        "kind": "definition",
                        "body": "A uniformly continuous function preserves nearby points.\n",
                    },
                )
                patched = await self._call_tool(
                    toolkit,
                    "kb_patch_metadata",
                    {
                        "root": str(root),
                        "node_id": "analysis.uniform_continuity",
                        "title": "Uniform continuity (updated)",
                        "summary": "Updated summary",
                        "tags": ["analysis"],
                    },
                )

                self.assertIsInstance(initialized, AftkToolSuccess)
                self.assertTrue(initialized.data["root_dir"].endswith("knowledgebase"))
                self.assertIsInstance(created, AftkToolSuccess)
                self.assertEqual(created.data["node"]["metadata"]["title"], "Uniform continuity")
                self.assertIsInstance(patched, AftkToolSuccess)
                self.assertEqual(patched.data["node"]["metadata"]["title"], "Uniform continuity (updated)")
                self.assertEqual(patched.data["node"]["metadata"]["summary"], "Updated summary")


if __name__ == "__main__":
    unittest.main()
