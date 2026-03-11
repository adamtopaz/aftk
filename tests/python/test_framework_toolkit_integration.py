from __future__ import annotations

import unittest
from pathlib import Path

from pydantic_ai import Agent
from pydantic_ai.messages import ModelRequest, ModelResponse, TextPart, ToolCallPart, ToolReturnPart
from pydantic_ai.models.function import AgentInfo, FunctionModel

from aftk.agents import build_toolkit_query_toolset
from aftk_client import AsyncAftkClient


REPO_ROOT = Path(__file__).resolve().parents[2]
KB_ROOT = REPO_ROOT / "tests" / "server" / "fixtures" / "knowledgebase" / "basic-valid"
INFORMAL_MODULES = ["AFTKTest.Informal.Fixtures.Basic"]


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


if __name__ == "__main__":
    unittest.main()
