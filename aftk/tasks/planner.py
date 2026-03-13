from __future__ import annotations

from collections.abc import Iterable, Mapping, Sequence
from typing import Any

from aftk.models import InformalDeclDepsResult, InformalRefDepsResult
from aftk.tasks.manager import TaskManager
from aftk.tasks.models import TaskRecord, TaskSpec


class TaskSeedError(ValueError):
    """Raised when seed task specifications are malformed."""


def normalize_task_specs(specs: Iterable[TaskSpec | Mapping[str, Any]]) -> list[TaskSpec]:
    return [spec if isinstance(spec, TaskSpec) else TaskSpec(**spec) for spec in specs]


def seed_manager(manager: TaskManager, specs: Iterable[TaskSpec | Mapping[str, Any]]) -> list[TaskRecord]:
    return manager.add_tasks(normalize_task_specs(specs))


def task_specs_from_informal_decl_deps(
    result: InformalDeclDepsResult,
    *,
    kind: str = "formalize_declaration",
    priority: int = 0,
    tag_prefix: str = "module",
) -> list[TaskSpec]:
    dependency_map = {row.decl_name: list(row.dependencies) for row in result.rows}
    decl_names = _ordered_keys(result.rows, result.leaves)
    return [
        TaskSpec(
            id=_decl_task_id(decl_name),
            kind=kind,
            title=f"Formalize declaration {decl_name}",
            payload={"decl_name": decl_name},
            tags=[f"{tag_prefix}:informal_decl"],
            priority=priority,
            depends_on=[_decl_task_id(dep) for dep in dependency_map.get(decl_name, [])],
        )
        for decl_name in decl_names
    ]


def task_specs_from_informal_ref_deps(
    result: InformalRefDepsResult,
    *,
    kind: str = "formalize_reference",
    priority: int = 0,
    tag_prefix: str = "knowledgebase",
) -> list[TaskSpec]:
    dependency_map = {row.ref: list(row.dependencies) for row in result.rows}
    refs = _ordered_keys(result.rows, result.leaves)
    return [
        TaskSpec(
            id=_ref_task_id(ref),
            kind=kind,
            title=f"Formalize reference {ref}",
            payload={"ref": ref},
            tags=[f"{tag_prefix}:informal_ref"],
            priority=priority,
            depends_on=[_ref_task_id(dep) for dep in dependency_map.get(ref, [])],
        )
        for ref in refs
    ]


def _ordered_keys(rows: Sequence[Any], leaves: Sequence[str]) -> list[str]:
    ordered: list[str] = []
    seen: set[str] = set()
    for row in rows:
        key = row.decl_name if hasattr(row, "decl_name") else row.ref
        if key not in seen:
            ordered.append(key)
            seen.add(key)
    for leaf in leaves:
        if leaf not in seen:
            ordered.append(leaf)
            seen.add(leaf)
    return ordered


def _decl_task_id(decl_name: str) -> str:
    return f"decl:{decl_name}"


def _ref_task_id(ref: str) -> str:
    return f"ref:{ref}"
