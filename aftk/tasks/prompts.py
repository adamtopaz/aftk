from __future__ import annotations

import json
from collections.abc import Sequence

from aftk.tasks.graph import scheduler_status
from aftk.tasks.manager import TaskManager
from aftk.tasks.models import TaskRecord


def render_task_prompt(
    task: TaskRecord,
    *,
    dependencies: Sequence[TaskRecord] = (),
    include_attempts: bool = True,
    include_artifacts: bool = False,
) -> str:
    lines = [
        "You are working on a task from the AFTK autoformalization task system.",
        "",
        f"Task ID: {task.id}",
        f"Kind: {task.kind}",
        f"Title: {task.title}",
        f"Priority: {task.priority}",
        f"Status: {task.status.value}",
    ]
    if task.description:
        lines.extend(["", "Description:", task.description])

    lines.extend(["", "Payload:", _render_json(task.payload)])

    if task.tags:
        lines.extend(["", f"Tags: {', '.join(task.tags)}"])

    if dependencies:
        lines.extend(["", "Dependencies:"])
        for dependency in dependencies:
            lines.append(
                f"- {dependency.id} [{dependency.status.value}] {dependency.title}"
            )
    else:
        lines.extend(["", "Dependencies: none"])

    if include_attempts and task.attempts:
        lines.extend(["", "Attempts:"])
        for attempt in task.attempts:
            summary = f" - {attempt.summary}" if attempt.summary else ""
            lines.append(f"- attempt {attempt.attempt}: {attempt.status.value}{summary}")
            if attempt.error_message:
                lines.append(f"  error: {attempt.error_message}")

    if include_artifacts and task.artifacts:
        lines.extend(["", "Artifacts:"])
        for artifact in task.artifacts:
            label = f" ({artifact.label})" if artifact.label else ""
            lines.append(f"- {artifact.kind}{label}: {_render_json(artifact.value)}")

    lines.extend(
        [
            "",
            "Produce the work for this specific task. If you complete it successfully, respond with the final result text.",
        ]
    )
    return "\n".join(lines)


def render_task_prompt_from_manager(
    manager: TaskManager,
    task_id: str,
    *,
    include_attempts: bool = True,
    include_artifacts: bool = False,
) -> str:
    task = manager.get_task(task_id)
    dependencies = manager.dependency_tasks(task_id)
    return render_task_prompt(
        task,
        dependencies=dependencies,
        include_attempts=include_attempts,
        include_artifacts=include_artifacts,
    )


def render_task_summary(manager: TaskManager, task_id: str) -> str:
    task = manager.get_task(task_id)
    status = manager.scheduler_status(task_id)
    return f"{task.id} [{status.value}] {task.title}"


def render_task_table(manager: TaskManager) -> str:
    lines = ["Tasks:"]
    for task in manager.list_tasks():
        status = scheduler_status(task, manager.state.tasks)
        lines.append(f"- {task.id} [{status.value}] priority={task.priority} title={task.title}")
    return "\n".join(lines)


def _render_json(value: object) -> str:
    if isinstance(value, str):
        return value
    return json.dumps(value, indent=2, sort_keys=True, default=str)
