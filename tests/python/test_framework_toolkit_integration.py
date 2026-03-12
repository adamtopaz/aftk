from __future__ import annotations

import asyncio
import unittest
from pathlib import Path

from pydantic_ai import Agent
from pydantic_ai.messages import ModelRequest, ModelResponse, RetryPromptPart, TextPart, ToolCallPart, ToolReturnPart
from pydantic_ai.models.function import AgentInfo, FunctionModel

from aftk.agents import build_toolkit_query_toolset
from aftk_client import AsyncAftkClient, CloseResult, LoadNodeResult, OpenResult
from aftk_client.errors import FileNotOpenError


REPO_ROOT = Path(__file__).resolve().parents[2]
KB_ROOT = REPO_ROOT / "tests" / "server" / "fixtures" / "knowledgebase" / "basic-valid"
INFORMAL_MODULES = ["AFTKTest.Informal.Fixtures.Basic"]


class SessionAwareToolkitClient:
    def __init__(self) -> None:
        self.calls: list[tuple[str, tuple[object, ...], dict[str, object]]] = []
        self.opened_paths: set[str] = set()

    async def open(self, path: str, *, timeout: float | None = None) -> OpenResult:
        self.calls.append(("open", (path,), {"timeout": timeout}))
        await asyncio.sleep(0)
        self.opened_paths.add(path)
        return OpenResult(path=path, opened=True)

    async def close(self, path: str, *, timeout: float | None = None) -> CloseResult:
        self.calls.append(("close", (path,), {"timeout": timeout}))
        self.opened_paths.discard(path)
        return CloseResult(path=path, closed=True)

    async def load_node(self, path: str, line: int, col: int, *, timeout: float | None = None) -> LoadNodeResult:
        self.calls.append(("load_node", (path, line, col), {"timeout": timeout}))
        if path not in self.opened_paths:
            raise FileNotOpenError(
                code=-32010,
                message="File is not open",
                data=path,
                method="load_node",
                request_id=1,
            )
        return LoadNodeResult(id=[f"node:{path}:{line}:{col}"])


class FrameworkToolkitIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def test_controlled_agent_can_use_real_toolkit_tools(self) -> None:
        def model_function(messages: list[ModelRequest | ModelResponse], info: AgentInfo) -> ModelResponse:
            seen_returns = {
                part.tool_name
                for message in messages
                if isinstance(message, ModelRequest)
                for part in message.parts
                if isinstance(part, ToolReturnPart)
            }
            if "knowledgebase_status" not in seen_returns:
                return ModelResponse(
                    parts=[
                        ToolCallPart(
                            tool_name="knowledgebase_status",
                            args={"root": str(KB_ROOT)},
                            tool_call_id="kb-status",
                        )
                    ]
                )
            if "informal_status" not in seen_returns:
                return ModelResponse(
                    parts=[
                        ToolCallPart(
                            tool_name="informal_status",
                            args={"modules": INFORMAL_MODULES},
                            tool_call_id="informal-status",
                        )
                    ]
                )
            return ModelResponse(parts=[TextPart(content="toolkit-ok")])

        async with AsyncAftkClient(project_root=REPO_ROOT) as client:
            agent = Agent(
                FunctionModel(model_function, model_name="function:toolkit-integration"),
                output_type=str,
                toolsets=[build_toolkit_query_toolset(client)],
            )
            result = await agent.run("Inspect the real toolkit fixtures.")

        self.assertEqual(result.output, "toolkit-ok")
        tool_returns = [
            part
            for message in result.all_messages()
            if isinstance(message, ModelRequest)
            for part in message.parts
            if isinstance(part, ToolReturnPart)
        ]
        self.assertEqual([part.tool_name for part in tool_returns], ["knowledgebase_status", "informal_status"])
        self.assertEqual(len(tool_returns), 2)

    async def test_toolkit_retry_prompt_guides_model_to_open_before_load_node(self) -> None:
        client = SessionAwareToolkitClient()

        def model_function(messages: list[ModelRequest | ModelResponse], info: AgentInfo) -> ModelResponse:
            tool_returns = [
                part
                for message in messages
                if isinstance(message, ModelRequest)
                for part in message.parts
                if isinstance(part, ToolReturnPart)
            ]
            retry_prompts = [
                part
                for message in messages
                if isinstance(message, ModelRequest)
                for part in message.parts
                if isinstance(part, RetryPromptPart)
            ]
            seen_tool_returns = {part.tool_name for part in tool_returns}
            if not retry_prompts:
                return ModelResponse(
                    parts=[
                        ToolCallPart(
                            tool_name="load_node",
                            args={"path": "Demo.lean", "line": 1, "col": 1},
                            tool_call_id="load-before-open",
                        )
                    ]
                )
            if "open" not in seen_tool_returns:
                return ModelResponse(
                    parts=[
                        ToolCallPart(
                            tool_name="open",
                            args={"path": "Demo.lean"},
                            tool_call_id="open-demo",
                        )
                    ]
                )
            if "load_node" not in seen_tool_returns:
                return ModelResponse(
                    parts=[
                        ToolCallPart(
                            tool_name="load_node",
                            args={"path": "Demo.lean", "line": 1, "col": 1},
                            tool_call_id="load-after-open",
                        )
                    ]
                )
            return ModelResponse(parts=[TextPart(content="recovered")])

        agent = Agent(
            FunctionModel(model_function, model_name="function:toolkit-retry"),
            output_type=str,
            toolsets=[build_toolkit_query_toolset(client)],
        )
        result = await agent.run("Inspect Demo.lean.")

        self.assertEqual(result.output, "recovered")
        retry_prompts = [
            part
            for message in result.all_messages()
            if isinstance(message, ModelRequest)
            for part in message.parts
            if isinstance(part, RetryPromptPart)
        ]
        self.assertEqual(len(retry_prompts), 1)
        self.assertEqual(retry_prompts[0].tool_name, "load_node")
        self.assertIn("Call open(path=...)", retry_prompts[0].model_response())
        self.assertEqual(
            [call[0] for call in client.calls],
            ["load_node", "open", "load_node"],
        )

    async def test_toolkit_toolset_runs_open_and_load_node_sequentially(self) -> None:
        client = SessionAwareToolkitClient()

        def model_function(messages: list[ModelRequest | ModelResponse], info: AgentInfo) -> ModelResponse:
            tool_returns = [
                part
                for message in messages
                if isinstance(message, ModelRequest)
                for part in message.parts
                if isinstance(part, ToolReturnPart)
            ]
            if not tool_returns:
                return ModelResponse(
                    parts=[
                        ToolCallPart(
                            tool_name="open",
                            args={"path": "Demo.lean"},
                            tool_call_id="open-demo",
                        ),
                        ToolCallPart(
                            tool_name="load_node",
                            args={"path": "Demo.lean", "line": 1, "col": 1},
                            tool_call_id="load-demo",
                        ),
                    ]
                )
            return ModelResponse(parts=[TextPart(content="sequential-ok")])

        agent = Agent(
            FunctionModel(model_function, model_name="function:toolkit-sequential"),
            output_type=str,
            toolsets=[build_toolkit_query_toolset(client)],
        )
        result = await agent.run("Open Demo.lean and inspect the first node.")

        self.assertEqual(result.output, "sequential-ok")
        self.assertEqual(
            [call[0] for call in client.calls],
            ["open", "load_node"],
        )


if __name__ == "__main__":
    unittest.main()
