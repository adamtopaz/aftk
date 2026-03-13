import { createToolkitTools, type CreateToolkitToolsOptions } from "../../toolkit/tools/aggregate.ts";
import type { ToolkitToolDefinition } from "../../toolkit/tools/common.ts";

export interface PiCommandContextLike {
  hasUI?: boolean;
  ui?: {
    notify: (message: string, level?: string) => void;
  };
}

export interface PiCommandDefinitionLike {
  description: string;
  handler: (args: string[], ctx: PiCommandContextLike) => Promise<void> | void;
}

export interface PiExtensionAPILike {
  registerTool: (tool: ToolkitToolDefinition) => void;
  registerCommand: (name: string, command: PiCommandDefinitionLike) => void;
  on: (event: "session_shutdown", handler: () => Promise<void> | void) => void;
}

export interface PiToolkitIntegration {
  customTools: ToolkitToolDefinition[];
  dispose: () => Promise<void>;
}

export function createPiToolkitCustomTools(options: CreateToolkitToolsOptions = {}): PiToolkitIntegration {
  const toolkit = createToolkitTools(options);
  return {
    customTools: toolkit.tools,
    dispose: toolkit.dispose,
  };
}

export function registerToolkitExtension(pi: PiExtensionAPILike, options: CreateToolkitToolsOptions = {}): PiToolkitIntegration {
  const integration = createPiToolkitCustomTools(options);

  for (const tool of integration.customTools) {
    pi.registerTool(tool);
  }

  pi.registerCommand("aftk-extension-stop", {
    description: "Stop the local AFTK toolkit resources managed by this extension",
    handler: async (_args, ctx) => {
      await integration.dispose();
      if (ctx.hasUI === true && ctx.ui !== undefined) {
        ctx.ui.notify("AFTK extension stopped", "info");
      }
    },
  });

  pi.on("session_shutdown", async () => {
    await integration.dispose();
  });

  return integration;
}

export {
  accumulateAgentRun,
  createRunId,
  createRunTotals,
  createUsageTotals,
  projectPath,
  registerAftkLoggingExtension,
  resolveCostDir,
  resolveLogsDir,
  resolveMirroredSessionLogFile,
  resolveRunCostFile,
  sanitizeFileToken,
  type AftkPiLoggingController,
  type AftkPiLoggingExtensionAPI,
  type AftkPiLoggingOptions,
  type AftkPiModelRunSummary,
  type AftkPiRunCostSummary,
  type AftkPiRunTotals,
  type AftkPiSessionDirectoryEvent,
  type AftkPiSessionDirectoryResult,
  type AftkPiUsageTotals,
} from "./logging.ts";
