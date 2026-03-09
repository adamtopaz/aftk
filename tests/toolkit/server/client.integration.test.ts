import test from "node:test";
import assert from "node:assert/strict";
import { AftkServerClient } from "../../../src/toolkit/server/client.ts";
import { repoPath } from "../support/helpers.ts";

test("AftkServerClient can talk to the real aftk_server", { concurrency: false, timeout: 180_000 }, async () => {
  const client = new AftkServerClient({ cwd: repoPath() });
  const file = repoPath("tests", "server", "fixtures", "lean", "Semantics.lean");

  try {
    const opened = await client.open({ path: file });
    assert.equal(opened.opened, true);

    const hover = await client.getHover({ path: file, line: 10, col: 26 });
    assert.ok(hover !== null);
    assert.match(hover.text, /Nat\.succ/);

    const node = await client.loadNode({ path: file, line: 16, col: 3 });
    assert.equal(node.id.length, 1);

    const goals = await client.getGoals({ path: file, id: node.id[0]! });
    assert.equal(goals.goals.length, 1);
    assert.match(goals.goals[0]!, /⊢ n \+ 0 = n/);

    const shutdown = await client.shutdown();
    assert.ok(shutdown.stopped >= 1);
    assert.equal(client.isRunning(), false);
  } finally {
    await client.stop(false);
  }
});
