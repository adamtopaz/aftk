import test from "node:test";
import assert from "node:assert/strict";
import * as path from "node:path";
import { findProjectRoot, resolveProjectRoot } from "../../../src/toolkit/runtime/project-root.ts";
import { ToolkitConfigError } from "../../../src/toolkit/runtime/errors.ts";
import { repoPath, repoRoot } from "../support/helpers.ts";

test("findProjectRoot discovers the repository root", () => {
  const start = repoPath("tests", "toolkit", "runtime");
  assert.equal(findProjectRoot(start), repoRoot);
});

test("resolveProjectRoot rejects directories without a lakefile", () => {
  const bogus = path.parse(repoRoot).root;
  assert.throws(() => resolveProjectRoot({ cwd: bogus }), ToolkitConfigError);
});
