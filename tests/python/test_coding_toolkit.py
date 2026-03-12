from __future__ import annotations

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any

from pydantic_ai import Agent
from pydantic_ai._run_context import RunContext
from pydantic_ai.models.test import TestModel
from pydantic_ai.usage import RunUsage

from aftk.toolkits.coding import CodingToolFailure, CodingToolSuccess, CodingToolkit


class ToolkitSchemaTests(unittest.IsolatedAsyncioTestCase):
    async def test_agent_exposes_default_coding_tools(self) -> None:
        with TemporaryDirectory() as tmpdir:
            model = TestModel(call_tools=[], custom_output_text="ok")
            toolkit = CodingToolkit(cwd=tmpdir)
            agent = Agent(model, toolsets=[toolkit])

            result = await agent.run("hello")

            self.assertEqual(result.output, "ok")
            assert model.last_model_request_parameters is not None
            tool_defs = {tool.name: tool for tool in model.last_model_request_parameters.function_tools}

            self.assertEqual(set(tool_defs), {"read", "write", "edit", "bash", "grep", "find", "ls"})
            self.assertTrue(tool_defs["read"].sequential)
            self.assertEqual(
                tool_defs["read"].metadata,
                {"source": "coding", "layer": "filesystem", "mutates": False, "read_only": True},
            )
            self.assertIn("oldText", tool_defs["edit"].parameters_json_schema["properties"])
            self.assertIn("newText", tool_defs["edit"].parameters_json_schema["properties"])
            self.assertIn("ignoreCase", tool_defs["grep"].parameters_json_schema["properties"])

    async def test_tool_profiles_filter_exposed_tools(self) -> None:
        with TemporaryDirectory() as tmpdir:
            model = TestModel(call_tools=[], custom_output_text="ok")
            read_only_toolkit = CodingToolkit(cwd=tmpdir, read_only=True, include_search=True)
            agent = Agent(model, toolsets=[read_only_toolkit])
            await agent.run("hello")

            assert model.last_model_request_parameters is not None
            read_only_names = {tool.name for tool in model.last_model_request_parameters.function_tools}
            self.assertEqual(read_only_names, {"read", "grep", "find", "ls"})

            write_model = TestModel(call_tools=[], custom_output_text="ok")
            write_toolkit = CodingToolkit(cwd=tmpdir, include_search=False)
            write_agent = Agent(write_model, toolsets=[write_toolkit])
            await write_agent.run("hello")

            assert write_model.last_model_request_parameters is not None
            write_names = {tool.name for tool in write_model.last_model_request_parameters.function_tools}
            self.assertEqual(write_names, {"read", "write", "edit", "bash"})


class ToolkitBehaviorTests(unittest.IsolatedAsyncioTestCase):
    def _context(self) -> RunContext[Any]:
        return RunContext(deps=None, model=TestModel(call_tools=[]), usage=RunUsage())

    async def _call_tool(self, toolkit: CodingToolkit, name: str, args: dict[str, Any]) -> Any:
        ctx = self._context()
        tools = await toolkit.get_tools(ctx)
        tool = tools[name]
        validated_args = tool.args_validator.validate_python(args)
        return await toolkit.call_tool(name, validated_args, ctx, tool)

    async def test_write_read_edit_and_ls(self) -> None:
        with TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            toolkit = CodingToolkit(cwd=root)

            write_result = await self._call_tool(
                toolkit,
                "write",
                {"path": "nested/example.txt", "content": "alpha\nbeta"},
            )
            self.assertIsInstance(write_result, CodingToolSuccess)
            self.assertEqual(write_result.data["path"], "nested/example.txt")
            self.assertTrue(write_result.data["created_parent_directories"])

            read_result = await self._call_tool(toolkit, "read", {"path": "nested/example.txt"})
            self.assertIsInstance(read_result, CodingToolSuccess)
            self.assertEqual(read_result.data["text"], "alpha\nbeta")
            self.assertEqual(read_result.data["total_lines"], 2)

            edit_result = await self._call_tool(
                toolkit,
                "edit",
                {"path": "nested/example.txt", "oldText": "beta", "newText": "gamma"},
            )
            self.assertIsInstance(edit_result, CodingToolSuccess)
            self.assertIn("+gamma", edit_result.data["diff"])
            self.assertEqual((root / "nested" / "example.txt").read_text(encoding="utf-8"), "alpha\ngamma")

            ls_result = await self._call_tool(toolkit, "ls", {"path": "nested"})
            self.assertIsInstance(ls_result, CodingToolSuccess)
            self.assertEqual(ls_result.data["text"], "example.txt")
            self.assertEqual(ls_result.data["entries_returned"], 1)

    async def test_read_truncation_and_offset_limit(self) -> None:
        with TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            big_path = root / "big.txt"
            big_path.write_text("\n".join(f"line {index}" for index in range(1, 2506)), encoding="utf-8")
            toolkit = CodingToolkit(cwd=root)

            first_result = await self._call_tool(toolkit, "read", {"path": "big.txt"})
            self.assertIsInstance(first_result, CodingToolSuccess)
            self.assertIn("Use offset=2001 to continue.", first_result.data["text"])
            self.assertIsNotNone(first_result.data["truncation"])

            window_result = await self._call_tool(toolkit, "read", {"path": "big.txt", "offset": 2001, "limit": 5})
            self.assertIsInstance(window_result, CodingToolSuccess)
            self.assertIn("line 2001", window_result.data["text"])
            self.assertIn("line 2005", window_result.data["text"])
            self.assertIn("[500 more lines in file. Use offset=2006 to continue.]", window_result.data["text"])

    async def test_edit_preserves_line_endings_and_reports_ambiguous_text(self) -> None:
        with TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            target = root / "crlf.txt"
            target.write_bytes(b"first\r\nsecond\r\n")
            toolkit = CodingToolkit(cwd=root)

            success = await self._call_tool(
                toolkit,
                "edit",
                {"path": "crlf.txt", "oldText": "second", "newText": "updated"},
            )
            self.assertIsInstance(success, CodingToolSuccess)
            self.assertIn(b"first\r\nupdated\r\n", target.read_bytes())

            ambiguous_path = root / "ambiguous.txt"
            ambiguous_path.write_text("x\ny\nx", encoding="utf-8")
            failure = await self._call_tool(
                toolkit,
                "edit",
                {"path": "ambiguous.txt", "oldText": "x", "newText": "z"},
            )
            self.assertIsInstance(failure, CodingToolFailure)
            self.assertEqual(failure.error.kind, "ambiguous_edit")
            self.assertTrue(failure.error.retryable)

    async def test_bash_success_failure_timeout_and_truncation(self) -> None:
        with TemporaryDirectory() as tmpdir:
            toolkit = CodingToolkit(cwd=tmpdir)

            success = await self._call_tool(toolkit, "bash", {"command": "printf 'hello\\n'"})
            self.assertIsInstance(success, CodingToolSuccess)
            self.assertEqual(success.data["text"], "hello\n")
            self.assertEqual(success.data["exit_code"], 0)

            failure = await self._call_tool(toolkit, "bash", {"command": "printf 'oops\\n'; exit 7"})
            self.assertIsInstance(failure, CodingToolFailure)
            self.assertEqual(failure.error.kind, "command_failed")
            self.assertEqual(failure.error.details["exit_code"], 7)
            self.assertIn("oops", failure.error.message)

            timeout = await self._call_tool(toolkit, "bash", {"command": "sleep 2", "timeout": 1})
            self.assertIsInstance(timeout, CodingToolFailure)
            self.assertEqual(timeout.error.kind, "timeout")
            self.assertTrue(timeout.error.retryable)

            long_output = await self._call_tool(
                toolkit,
                "bash",
                {"command": "i=1; while [ $i -le 2505 ]; do echo line-$i; i=$((i+1)); done"},
            )
            self.assertIsInstance(long_output, CodingToolSuccess)
            self.assertIsNotNone(long_output.data["truncation"])
            full_output_path = long_output.data["full_output_path"]
            self.assertIsNotNone(full_output_path)
            self.assertTrue(Path(full_output_path).exists())
            self.assertIn("Full output:", long_output.data["text"])

    async def test_grep_find_and_gitignore(self) -> None:
        with TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            (root / ".gitignore").write_text("ignored.txt\n", encoding="utf-8")
            (root / "sub").mkdir()
            (root / "sub" / ".gitignore").write_text("hidden.md\n", encoding="utf-8")
            (root / "visible.txt").write_text("needle here\n", encoding="utf-8")
            (root / "ignored.txt").write_text("needle hidden\n", encoding="utf-8")
            (root / "sub" / "visible.md").write_text(
                "before\nneedle " + ("x" * 700) + "\nafter\n",
                encoding="utf-8",
            )
            (root / "sub" / "hidden.md").write_text("needle in hidden markdown\n", encoding="utf-8")

            toolkit = CodingToolkit(cwd=root)

            grep_result = await self._call_tool(
                toolkit,
                "grep",
                {"pattern": "needle", "literal": True, "context": 1},
            )
            self.assertIsInstance(grep_result, CodingToolSuccess)
            self.assertIn("visible.txt:1: needle here", grep_result.data["text"])
            self.assertIn("sub/visible.md:2:", grep_result.data["text"])
            self.assertNotIn("ignored.txt", grep_result.data["text"])
            self.assertNotIn("hidden.md", grep_result.data["text"])
            self.assertTrue(grep_result.data["lines_truncated"])

            find_result = await self._call_tool(toolkit, "find", {"pattern": "*.md"})
            self.assertIsInstance(find_result, CodingToolSuccess)
            self.assertEqual(find_result.data["text"], "sub/visible.md")

            relaxed_toolkit = CodingToolkit(cwd=root, follow_gitignore=False)
            relaxed_find = await self._call_tool(relaxed_toolkit, "find", {"pattern": "*.md"})
            self.assertIsInstance(relaxed_find, CodingToolSuccess)
            self.assertIn("sub/hidden.md", relaxed_find.data["text"])
            self.assertIn("sub/visible.md", relaxed_find.data["text"])


if __name__ == "__main__":
    unittest.main()
