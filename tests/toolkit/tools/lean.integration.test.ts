import test from "node:test";
import assert from "node:assert/strict";
import { createAftkLeanTools } from "../../../src/toolkit/tools/lean.ts";
import { executeTool, repoPath, textOf } from "../support/helpers.ts";

test("Lean tool family exposes the expected aftk_* surface", () => {
  const toolset = createAftkLeanTools({ cwd: repoPath() });
  const names = toolset.tools.map((tool) => tool.name);
  assert.deepEqual(names, [
    "aftk_open",
    "aftk_close",
    "aftk_load_node",
    "aftk_get_hover",
    "aftk_get_plain_goal",
    "aftk_get_plain_term_goal",
    "aftk_get_infoview",
    "aftk_get_goals",
    "aftk_run_tactic",
    "aftk_run_tactic_steps",
    "aftk_shutdown",
  ]);
});

test("Lean tools can query the real server-backed surface", { concurrency: false, timeout: 180_000 }, async () => {
  const toolset = createAftkLeanTools({ cwd: repoPath() });
  const semantics = repoPath("tests", "server", "fixtures", "lean", "Semantics.lean");
  const informal = repoPath("tests", "server", "fixtures", "lean", "Informal.lean");

  try {
    const openResult = await executeTool(toolset.tools, "aftk_open", { path: `@${semantics}` });
    assert.equal(openResult.details.ok, true);
    assert.match(textOf(openResult), /Opened file worker|File already open/);

    const hoverResult = await executeTool(toolset.tools, "aftk_get_hover", {
      path: informal,
      line: 12,
      col: 38,
    });
    assert.equal(hoverResult.details.ok, false);

    const openInformal = await executeTool(toolset.tools, "aftk_open", { path: informal });
    assert.equal(openInformal.details.ok, true);

    const richHover = await executeTool(toolset.tools, "aftk_get_hover", {
      path: informal,
      line: 12,
      col: 38,
    });
    assert.equal(richHover.details.ok, true);
    assert.match(textOf(richHover), /Informal node:/);

    const loadNode = await executeTool(toolset.tools, "aftk_load_node", {
      path: semantics,
      line: 16,
      col: 3,
    });
    assert.equal(loadNode.details.ok, true);
    if (!loadNode.details.ok) throw new Error("unreachable");
    const loadNodeResult = loadNode.details.result as { id: string[] };
    const nodeId = loadNodeResult.id[0]!;

    const tactic = await executeTool(toolset.tools, "aftk_run_tactic", {
      path: semantics,
      id: nodeId,
      tactic: "simpa",
    });
    assert.equal(tactic.details.ok, true);
    assert.match(textOf(tactic), /nextId:/);
  } finally {
    await toolset.shutdown(false);
  }
});
