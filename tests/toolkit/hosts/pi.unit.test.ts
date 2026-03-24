import test from "node:test";
import assert from "node:assert/strict";
import { registerToolkitExtension, type PiExtensionAPILike } from "../../../src/hosts/pi/index.ts";
import { repoPath } from "../support/helpers.ts";

test("registerToolkitExtension mounts tools, stop command, and noninteractive cleanup hooks", async () => {
  const tools: string[] = [];
  const commands = new Map<string, { description: string; handler: (args: string[], ctx: any) => Promise<void> | void }>();
  const events = new Map<string, (...args: any[]) => Promise<void> | void>();

  const pi: PiExtensionAPILike = {
    registerTool(tool) {
      tools.push(tool.name);
    },
    registerCommand(name, command) {
      commands.set(name, command);
    },
    on(event, handler) {
      events.set(event, handler);
    },
  };

  const integration = registerToolkitExtension(pi, {
    cwd: repoPath(),
    families: { lean: true, knowledgebase: false, informal: false },
  });

  assert.deepEqual(tools, [
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
  assert.ok(commands.has("aftk-extension-stop"));
  assert.ok(events.has("session_shutdown"));
  assert.ok(events.has("agent_end"));

  let notified = false;
  await commands.get("aftk-extension-stop")?.handler([], {
    hasUI: true,
    ui: {
      notify() {
        notified = true;
      },
    },
  });
  assert.equal(notified, true);

  await events.get("session_shutdown")?.();
  await integration.dispose();
});
