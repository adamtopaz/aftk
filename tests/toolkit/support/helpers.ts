import assert from "node:assert/strict";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import type { ToolkitToolDefinition } from "../../../src/toolkit/tools/common.ts";
import type { ToolkitToolResult } from "../../../src/toolkit/output/result.ts";

const thisDir = path.dirname(fileURLToPath(import.meta.url));
export const repoRoot = path.resolve(thisDir, "../../..");

export function repoPath(...segments: string[]): string {
  return path.join(repoRoot, ...segments);
}

export function textOf(result: ToolkitToolResult): string {
  return result.content[0].text;
}

export async function executeTool(
  tools: ToolkitToolDefinition[],
  name: string,
  params: Record<string, unknown>,
): Promise<ToolkitToolResult> {
  const tool = tools.find((candidate) => candidate.name === name);
  assert.ok(tool, `Missing tool '${name}'.`);
  return await tool.execute("test-call", params, undefined, undefined, undefined);
}
