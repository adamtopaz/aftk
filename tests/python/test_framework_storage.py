from __future__ import annotations

import json
import tempfile
import unittest
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

from aftk.config import FrameworkConfig
from aftk.storage import (
    AgentRole,
    LlmCallRecord,
    LlmCallStatus,
    ModelPricingRule,
    PricingTable,
    ProjectRollupService,
    RunCollection,
    RunStatus,
    RunTelemetrySession,
    ToolCallRecord,
    ToolCallStatus,
    ToolFamily,
    UsageSummary,
    estimate_usage_cost,
)


def make_config(root: Path) -> FrameworkConfig:
    root.mkdir(parents=True, exist_ok=True)
    (root / "lakefile.toml").write_text('name = "demo"\n', encoding="utf-8")
    (root / "entrypoint.md").write_text("# Demo\n", encoding="utf-8")
    return FrameworkConfig.from_project_root(root)


@dataclass(frozen=True)
class FakeRunUsage:
    input_tokens: int = 0
    output_tokens: int = 0
    requests: int = 0
    tool_calls: int = 0
    details: dict[str, int] | None = None


class FakeRunResult:
    def __init__(self, messages: bytes, usage: FakeRunUsage) -> None:
        self._messages = messages
        self._usage = usage

    def new_messages_json(self, *, output_tool_return_content: str | None = None) -> bytes:
        return self._messages

    def usage(self) -> FakeRunUsage:
        return self._usage


class RunTelemetryTests(unittest.TestCase):
    def test_run_session_persists_artifacts_and_rolls_up_usage_and_cost(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            collection = RunCollection(config)
            pricing = PricingTable(
                source="tests",
                rules=[
                    ModelPricingRule(
                        model_pattern="openai:gpt-4o-mini",
                        input_cost_per_million_tokens=0.15,
                        output_cost_per_million_tokens=0.60,
                    )
                ],
            )

            run_id = collection.next_run_id()
            self.assertEqual(run_id, "run-0001")
            store = collection.run_store(run_id)
            session = RunTelemetrySession(store, pricing_table=pricing)

            started = datetime(2026, 1, 1, tzinfo=timezone.utc)
            record = session.start_run(
                agent_role=AgentRole.WORKER,
                model_name="openai:gpt-4o-mini",
                task_id="task-0001",
                attempt_id="attempt-0001",
                now=started,
                metadata={"phase": "worker"},
            )
            self.assertEqual(record.artifacts.messages_path, ".aftk/runs/run-0001/messages.json")

            fake_result = FakeRunResult(
                b'[{"kind":"request"}]',
                FakeRunUsage(input_tokens=11, output_tokens=7, requests=1),
            )
            self.assertEqual(session.usage_from_result(fake_result).input_tokens, 11)
            session.save_messages_from_result(fake_result)
            session.save_result_payload({"outcome": "completed", "summary": "done"})

            session.append_llm_call(
                LlmCallRecord(
                    index=1,
                    run_id=run_id,
                    agent_role="worker",
                    task_id="task-0001",
                    attempt_id="attempt-0001",
                    model_name="openai:gpt-4o-mini",
                    started_at=started,
                    finished_at=started + timedelta(seconds=1),
                    duration_seconds=1.0,
                    status=LlmCallStatus.SUCCEEDED,
                    usage=UsageSummary(input_tokens=100, output_tokens=25),
                    request_summary="first request",
                    response_summary="first response",
                )
            )
            session.append_llm_call(
                LlmCallRecord(
                    index=2,
                    run_id=run_id,
                    agent_role="worker",
                    task_id="task-0001",
                    attempt_id="attempt-0001",
                    model_name="openai:gpt-4o-mini",
                    started_at=started + timedelta(seconds=2),
                    finished_at=started + timedelta(seconds=3),
                    duration_seconds=1.0,
                    status=LlmCallStatus.SUCCEEDED,
                    usage=UsageSummary(input_tokens=40, output_tokens=10),
                    request_summary="second request",
                    response_summary="second response",
                )
            )
            session.append_tool_call(
                ToolCallRecord(
                    index=1,
                    run_id=run_id,
                    agent_role="worker",
                    task_id="task-0001",
                    attempt_id="attempt-0001",
                    tool_name="lake_build",
                    tool_family=ToolFamily.CODING,
                    started_at=started + timedelta(seconds=4),
                    finished_at=started + timedelta(seconds=5),
                    duration_seconds=1.0,
                    status=ToolCallStatus.SUCCEEDED,
                    input_summary={"target": "Demo"},
                    output_summary={"exit_code": 0},
                )
            )

            finished = session.finalize_run(status=RunStatus.COMPLETED, now=started + timedelta(seconds=30))

            self.assertTrue(store.run_record_path.exists())
            self.assertTrue(store.result_path.exists())
            self.assertTrue(store.messages_path.exists())
            self.assertTrue(store.llm_calls_path.exists())
            self.assertTrue(store.tool_calls_path.exists())
            self.assertTrue(store.usage_path.exists())
            self.assertTrue(store.cost_path.exists())
            self.assertEqual(store.load_messages_bytes(), b'[{"kind":"request"}]')
            self.assertEqual(store.load_result_payload()["outcome"], "completed")

            self.assertEqual(finished.status, RunStatus.COMPLETED)
            self.assertEqual(finished.duration_seconds, 30.0)
            self.assertIsNotNone(finished.usage_summary)
            self.assertEqual(finished.usage_summary.requests, 2)
            self.assertEqual(finished.usage_summary.tool_calls, 1)
            self.assertEqual(finished.usage_summary.input_tokens, 140)
            self.assertEqual(finished.usage_summary.output_tokens, 35)
            self.assertIsNotNone(finished.cost_summary)
            self.assertAlmostEqual(finished.cost_summary.total_cost, 0.000042)

    def test_pricing_table_override_file_takes_precedence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            override_path = Path(tmp) / "pricing-overrides.json"
            override_path.write_text(
                json.dumps(
                    {
                        "currency": "USD",
                        "rules": [
                            {
                                "model_pattern": "openai:gpt-4o-mini",
                                "input_cost_per_million_tokens": 3.0,
                                "output_cost_per_million_tokens": 4.0,
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )

            base = PricingTable(
                source="base",
                rules=[
                    ModelPricingRule(
                        model_pattern="openai:*",
                        input_cost_per_million_tokens=1.0,
                        output_cost_per_million_tokens=2.0,
                    )
                ],
            )
            merged = base.with_override_file(override_path)

            exact_cost = estimate_usage_cost(
                UsageSummary(input_tokens=1_000_000, output_tokens=1_000_000),
                model_name="openai:gpt-4o-mini",
                pricing_table=merged,
            )
            wildcard_cost = estimate_usage_cost(
                UsageSummary(input_tokens=1_000_000, output_tokens=1_000_000),
                model_name="openai:gpt-4.1-mini",
                pricing_table=merged,
            )

            self.assertAlmostEqual(exact_cost.total_cost, 7.0)
            self.assertAlmostEqual(wildcard_cost.total_cost, 3.0)
            self.assertEqual(exact_cost.pricing_source, str(override_path.resolve()))

    def test_project_rollups_aggregate_by_run_attempt_role_model_and_project(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "project"
            config = make_config(root)
            collection = RunCollection(config)
            pricing = PricingTable(
                source="tests",
                rules=[
                    ModelPricingRule(
                        model_pattern="openai:gpt-4o-mini",
                        input_cost_per_million_tokens=0.15,
                        output_cost_per_million_tokens=0.60,
                    ),
                    ModelPricingRule(
                        model_pattern="anthropic:claude-3.5-sonnet",
                        input_cost_per_million_tokens=3.0,
                        output_cost_per_million_tokens=15.0,
                    ),
                ],
            )
            started = datetime(2026, 1, 1, tzinfo=timezone.utc)

            orchestrator_session = RunTelemetrySession(collection.run_store(collection.next_run_id()), pricing_table=pricing)
            orchestrator_session.start_run(
                agent_role=AgentRole.ORCHESTRATOR,
                model_name="openai:gpt-4o-mini",
                now=started,
            )
            orchestrator_session.append_llm_call(
                LlmCallRecord(
                    index=1,
                    run_id="run-0001",
                    agent_role="orchestrator",
                    model_name="openai:gpt-4o-mini",
                    started_at=started,
                    finished_at=started + timedelta(seconds=1),
                    duration_seconds=1.0,
                    status=LlmCallStatus.SUCCEEDED,
                    usage=UsageSummary(input_tokens=10, output_tokens=5),
                    request_summary="plan",
                    response_summary="decision",
                )
            )
            orchestrator_session.finalize_run(status=RunStatus.COMPLETED, now=started + timedelta(seconds=2))

            worker_session = RunTelemetrySession(collection.run_store(collection.next_run_id()), pricing_table=pricing)
            worker_session.start_run(
                agent_role=AgentRole.WORKER,
                model_name="anthropic:claude-3.5-sonnet",
                task_id="task-0001",
                attempt_id="attempt-0001",
                now=started + timedelta(minutes=1),
            )
            worker_session.append_llm_call(
                LlmCallRecord(
                    index=1,
                    run_id="run-0002",
                    agent_role="worker",
                    task_id="task-0001",
                    attempt_id="attempt-0001",
                    model_name="anthropic:claude-3.5-sonnet",
                    started_at=started + timedelta(minutes=1),
                    finished_at=started + timedelta(minutes=1, seconds=1),
                    duration_seconds=1.0,
                    status=LlmCallStatus.SUCCEEDED,
                    usage=UsageSummary(input_tokens=20, output_tokens=10),
                    request_summary="work",
                    response_summary="partial",
                )
            )
            worker_session.append_llm_call(
                LlmCallRecord(
                    index=2,
                    run_id="run-0002",
                    agent_role="worker",
                    task_id="task-0001",
                    attempt_id="attempt-0001",
                    model_name="anthropic:claude-3.5-sonnet",
                    started_at=started + timedelta(minutes=1, seconds=2),
                    finished_at=started + timedelta(minutes=1, seconds=3),
                    duration_seconds=1.0,
                    status=LlmCallStatus.SUCCEEDED,
                    usage=UsageSummary(input_tokens=5, output_tokens=5),
                    request_summary="retry",
                    response_summary="done",
                )
            )
            worker_session.append_tool_call(
                ToolCallRecord(
                    index=1,
                    run_id="run-0002",
                    agent_role="worker",
                    task_id="task-0001",
                    attempt_id="attempt-0001",
                    tool_name="read_file",
                    tool_family=ToolFamily.CODING,
                    started_at=started + timedelta(minutes=1, seconds=4),
                    finished_at=started + timedelta(minutes=1, seconds=5),
                    duration_seconds=1.0,
                    status=ToolCallStatus.SUCCEEDED,
                    input_summary={"path": "Demo.lean"},
                    output_summary={"bytes": 42},
                )
            )
            worker_session.finalize_run(status=RunStatus.COMPLETED, now=started + timedelta(minutes=1, seconds=10))

            rollup_service = ProjectRollupService(collection, pricing_table=pricing)
            rollups = rollup_service.rebuild_rollups()

            self.assertTrue(collection.rollups_path.exists())
            self.assertEqual(set(rollups.by_run), {"run-0001", "run-0002"})
            self.assertEqual(rollups.by_run["run-0001"].usage.input_tokens, 10)
            self.assertEqual(rollups.by_run["run-0002"].usage.input_tokens, 25)
            self.assertEqual(rollups.by_attempt["attempt-0001"].usage.output_tokens, 15)
            self.assertEqual(rollups.by_agent_role["orchestrator"].run_count, 1)
            self.assertEqual(rollups.by_agent_role["worker"].tool_call_count, 1)
            self.assertEqual(rollups.by_model["openai:gpt-4o-mini"].usage.input_tokens, 10)
            self.assertEqual(rollups.by_model["anthropic:claude-3.5-sonnet"].usage.input_tokens, 25)
            self.assertAlmostEqual(rollups.by_model["anthropic:claude-3.5-sonnet"].total_cost, 0.0003)
            self.assertEqual(rollups.project.usage.requests, 3)
            self.assertEqual(rollups.project.tool_call_count, 1)


if __name__ == "__main__":
    unittest.main()
