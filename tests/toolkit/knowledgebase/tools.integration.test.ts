import test from "node:test";
import assert from "node:assert/strict";
import { createKnowledgeBaseTools } from "../../../src/toolkit/tools/knowledgebase.ts";
import { executeTool, repoPath, textOf } from "../support/helpers.ts";

test("Knowledge-base tools expose the expected initial surface", () => {
  const toolset = createKnowledgeBaseTools({ cwd: repoPath() });
  const names = toolset.tools.map((tool) => tool.name);
  assert.deepEqual(names, [
    "knowledgebase_status",
    "knowledgebase_list",
    "knowledgebase_show",
    "knowledgebase_search_text",
    "knowledgebase_search_tag",
    "knowledgebase_relationships",
    "knowledgebase_validate_storage",
    "knowledgebase_validate_node",
    "knowledgebase_validate_metadata",
    "knowledgebase_validate_all",
  ]);
});

test("Knowledge-base tools query the real CLI and preserve validation-report success semantics", async () => {
  const toolset = createKnowledgeBaseTools({ cwd: repoPath() });
  const validRoot = repoPath("tests", "informal", "knowledgebase-fixtures", "basic-valid");
  const invalidRoot = repoPath("tests", "informal", "knowledgebase-fixtures", "malformed-node");

  const status = await executeTool(toolset.tools, "knowledgebase_status", { root: validRoot });
  assert.equal(status.details.ok, true);
  assert.match(textOf(status), /Knowledge base root:/);

  const search = await executeTool(toolset.tools, "knowledgebase_search_text", {
    root: validRoot,
    query: "group",
    limit: 5,
  });
  assert.equal(search.details.ok, true);
  assert.match(textOf(search), /Text search hits:/);

  const validate = await executeTool(toolset.tools, "knowledgebase_validate_all", { root: invalidRoot });
  assert.equal(validate.details.ok, true);
  if (!validate.details.ok) throw new Error("unreachable");
  const validationResult = validate.details.result as { report: { ok: boolean } };
  assert.equal(validate.details.backend.kind, "knowledgebase_cli");
  assert.equal(validate.details.backend.exitCode, 4);
  assert.equal(validationResult.report.ok, false);
});
