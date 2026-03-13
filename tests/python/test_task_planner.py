from __future__ import annotations

import unittest

from aftk.models import InformalDeclDepsResult, InformalRefDepsResult
from aftk.tasks.planner import (
    task_specs_from_informal_decl_deps,
    task_specs_from_informal_ref_deps,
)


class TaskPlannerTests(unittest.TestCase):
    def test_informal_decl_dependencies_become_task_specs(self) -> None:
        result = InformalDeclDepsResult.model_validate(
            {
                "rows": [
                    {"declName": "Demo.b", "dependencies": ["Demo.a"]},
                    {"declName": "Demo.a", "dependencies": []},
                ],
                "leaves": ["Demo.a"],
            }
        )

        specs = task_specs_from_informal_decl_deps(result)

        self.assertEqual([spec.id for spec in specs], ["decl:Demo.b", "decl:Demo.a"])
        self.assertEqual(specs[0].depends_on, ["decl:Demo.a"])

    def test_informal_ref_dependencies_become_task_specs(self) -> None:
        result = InformalRefDepsResult.model_validate(
            {
                "rows": [
                    {"ref": "group.basic.theorem", "dependencies": ["group.basic.definition"]},
                    {"ref": "group.basic.definition", "dependencies": []},
                ],
                "leaves": ["group.basic.definition"],
            }
        )

        specs = task_specs_from_informal_ref_deps(result)

        self.assertEqual([spec.id for spec in specs], ["ref:group.basic.theorem", "ref:group.basic.definition"])
        self.assertEqual(specs[0].depends_on, ["ref:group.basic.definition"])


if __name__ == "__main__":
    unittest.main()
