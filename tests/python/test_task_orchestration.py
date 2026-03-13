from __future__ import annotations

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from pydantic_ai.models.test import TestModel

from aftk.app import build_agent, build_model_settings
from aftk.tasks.manager import TaskManager, execute_ready_tasks_until_blocked
from aftk.tasks.models import TaskArtifact, TaskExecutionResult, TaskExecutionStatus, TaskSpec
from aftk.tasks.prompts import render_task_prompt_from_manager
from aftk.tasks.store import InMemoryTaskRunStore


REPO_ROOT = Path(__file__).resolve().parents[2]


class TaskOrchestrationTests(unittest.IsolatedAsyncioTestCase):
    async def test_execute_ready_tasks_until_blocked_runs_dependency_chain(self) -> None:
        manager = TaskManager.create(InMemoryTaskRunStore(), "run-1")
        manager.add_tasks(
            [
                TaskSpec(id="task-1", kind="seed", title="Task 1"),
                TaskSpec(id="task-2", kind="seed", title="Task 2", depends_on=["task-1"]),
            ]
        )

        async def executor(task):
            return TaskExecutionResult(
                status=TaskExecutionStatus.completed,
                summary=f"completed {task.id}",
                artifacts=[TaskArtifact(kind="output", value=task.id)],
            )

        finished = await execute_ready_tasks_until_blocked(manager, executor, runner_id="runner")

        self.assertEqual([task.id for task in finished], ["task-1", "task-2"])
        self.assertEqual(manager.get_task("task-2").artifacts[-1].value, "task-2")

    async def test_task_prompt_can_drive_existing_agent(self) -> None:
        manager = TaskManager.create(InMemoryTaskRunStore(), "run-1")
        manager.add_task(
            TaskSpec(
                id="task-1",
                kind="formalize_reference",
                title="Formalize group.basic.definition",
                payload={"ref": "group.basic.definition"},
            )
        )

        with TemporaryDirectory() as tmpdir:
            agent = build_agent(cwd=tmpdir, base_dir=REPO_ROOT)
            model = TestModel(call_tools=[], custom_output_text="agent completed task")

            async def executor(task):
                prompt = render_task_prompt_from_manager(manager, task.id)
                result = await agent.run(
                    prompt,
                    model=model,
                    model_settings=build_model_settings("low"),
                )
                return TaskExecutionResult(
                    summary=result.output,
                    artifacts=[TaskArtifact(kind="agent_output", value=result.output)],
                )

            finished = await execute_ready_tasks_until_blocked(manager, executor, runner_id="agent")

            self.assertEqual(len(finished), 1)
            self.assertEqual(finished[0].status.value, "completed")
            self.assertEqual(manager.get_task("task-1").result_summary, "agent completed task")


if __name__ == "__main__":
    unittest.main()
