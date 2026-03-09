import { runCommand, type CompletedCommand, type RunCommandOptions } from "./subprocess.ts";
import type { ToolkitRuntimeContext } from "./options.ts";

export type ToolkitCliFamily = "knowledgebase" | "informal";

export async function runToolkitCliCommand(
  runtime: ToolkitRuntimeContext,
  family: ToolkitCliFamily,
  args: string[],
  options: RunCommandOptions = {},
): Promise<CompletedCommand> {
  return await runCommand(runtime, runtime.executables[family], args, options);
}
