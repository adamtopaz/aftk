import test from "node:test";
import assert from "node:assert/strict";
import { AftkServerClient, AftkServerProtocolError } from "../../../src/toolkit/server/client.ts";
import { repoPath } from "../support/helpers.ts";

test("AftkServerClient treats malformed stdout as protocol failure", async () => {
  const fixture = repoPath("tests", "toolkit", "fixtures", "process", "malformed-jsonrpc.mjs");
  const client = new AftkServerClient({
    cwd: repoPath(),
    executables: {
      hub: {
        command: "node",
        args: [fixture],
        label: "malformed-jsonrpc-fixture",
      },
    },
  });

  await assert.rejects(
    () => client.request("open", { path: "Foo.lean" }),
    (error: unknown) => {
      assert.ok(error instanceof AftkServerProtocolError);
      return true;
    },
  );

  await client.stop(false);
});
