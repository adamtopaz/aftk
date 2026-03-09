import test from "node:test";
import assert from "node:assert/strict";
import { createInformalTools } from "../../../src/toolkit/tools/informal.ts";
import { executeTool, repoPath, textOf } from "../support/helpers.ts";

test("Informal tools expose the expected initial surface", () => {
  const toolset = createInformalTools({ cwd: repoPath() });
  const names = toolset.tools.map((tool) => tool.name);
  assert.deepEqual(names, [
    "informal_status",
    "informal_decls",
    "informal_decl",
    "informal_refs",
    "informal_ref",
    "informal_deps",
    "informal_present",
  ]);
});

test("Informal tools query the real CLI surface", async () => {
  const toolset = createInformalTools({ cwd: repoPath() });

  const status = await executeTool(toolset.tools, "informal_status", {
    modules: ["AFTKTest.Informal.Fixtures.Basic"],
  });
  assert.equal(status.details.ok, true);
  assert.match(textOf(status), /Tracked declarations:/);

  const deps = await executeTool(toolset.tools, "informal_deps", {
    modules: ["AFTKTest.Informal.Fixtures.Imports.Top"],
    mode: "ref",
  });
  assert.equal(deps.details.ok, true);
  assert.match(textOf(deps), /Reference dependencies/);

  const present = await executeTool(toolset.tools, "informal_present", {
    ref: "analysis.uniform_continuity",
    root: repoPath("tests", "informal", "knowledgebase-fixtures", "long-body"),
    mode: "rich",
    body: "preview",
  });
  assert.equal(present.details.ok, true);
  assert.match(textOf(present), /\[truncated\]/);
  if (!present.details.ok) throw new Error("unreachable");
  const presentResult = present.details.result as {
    mode: string;
    payload: { body: { kind: string; truncated?: boolean } };
  };
  assert.equal(presentResult.mode, "rich");
  assert.equal(presentResult.payload.body.kind, "preview");
  assert.equal(presentResult.payload.body.truncated, true);
});
