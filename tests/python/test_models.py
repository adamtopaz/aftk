from __future__ import annotations

import unittest

from pydantic import ValidationError

from aftk_client.models import (
    FileLocationParams,
    InfoViewResult,
    InformalDeclDto,
    InformalModulesParams,
    InformalPresentResult,
    KnowledgeBaseCreateParams,
    LoadNodeResult,
    NodeMetadata,
    RunTacticResult,
    RunTacticStepsParams,
)


class ModelTests(unittest.TestCase):
    def test_file_location_rejects_zero_based_positions(self) -> None:
        with self.assertRaises(ValidationError):
            FileLocationParams(path="/tmp/Test.lean", line=0, col=1)

        with self.assertRaises(ValidationError):
            FileLocationParams(path="/tmp/Test.lean", line=1, col=0)

    def test_run_tactic_steps_requires_non_empty_tactics(self) -> None:
        with self.assertRaises(ValidationError):
            RunTacticStepsParams(path="/tmp/Test.lean", node_id="node-0", tactics=[])

    def test_aliases_round_trip(self) -> None:
        result = RunTacticResult.model_validate({"goals": [], "nextId": "node-1"})
        self.assertEqual(result.next_id, "node-1")
        self.assertEqual(result.model_dump(by_alias=True), {"goals": [], "nextId": "node-1"})

        loaded = LoadNodeResult.model_validate({"id": ["node-0"]})
        self.assertEqual(loaded.ids, ["node-0"])
        self.assertEqual(loaded.model_dump(by_alias=True), {"id": ["node-0"]})

    def test_infoview_allows_missing_optional_fields(self) -> None:
        infoview = InfoViewResult.model_validate({})
        self.assertIsNone(infoview.hover)
        self.assertIsNone(infoview.plain_goal)
        self.assertIsNone(infoview.plain_term_goal)

    def test_informal_modules_require_non_empty_list(self) -> None:
        with self.assertRaises(ValidationError):
            InformalModulesParams(modules=[])

    def test_knowledgebase_create_and_metadata_aliases(self) -> None:
        params = KnowledgeBaseCreateParams(id="group.basic.definition", title="Definition")
        self.assertEqual(
            params.model_dump(by_alias=True, exclude_none=True),
            {"id": "group.basic.definition", "title": "Definition"},
        )

        metadata = NodeMetadata.model_validate(
            {
                "schemaVersion": 1,
                "id": "group.basic.definition",
                "title": "Definition of group",
                "leanRefs": [{"declaration": "demoDecl"}],
            }
        )
        self.assertEqual(metadata.schema_version, 1)
        self.assertEqual(metadata.lean_refs[0].declaration, "demoDecl")
        self.assertEqual(metadata.model_dump(by_alias=True)["leanRefs"][0]["declaration"], "demoDecl")

    def test_informal_transport_models_decode_aliases(self) -> None:
        decl = InformalDeclDto.model_validate(
            {"declName": "Demo.basic", "refs": ["group.basic.definition"], "refCount": 1}
        )
        self.assertEqual(decl.decl_name, "Demo.basic")
        self.assertEqual(decl.model_dump(by_alias=True)["refCount"], 1)

        present = InformalPresentResult.model_validate(
            {
                "mode": "rich",
                "summary": {"ref": "group.basic.definition", "title": "Definition of group"},
                "bodyMode": "preview",
            }
        )
        self.assertEqual(present.body_mode, "preview")
        self.assertEqual(present.summary.title, "Definition of group")


if __name__ == "__main__":
    unittest.main()
