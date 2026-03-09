import { createToolkitRuntimeContext, type ToolkitRuntimeContext, type ToolkitRuntimeOptions } from "../runtime/options.ts";
import { createAftkLeanTools, type CreateAftkLeanToolsOptions } from "./lean.ts";
import { createKnowledgeBaseTools, type CreateKnowledgeBaseToolsOptions } from "./knowledgebase.ts";
import { createInformalTools, type CreateInformalToolsOptions } from "./informal.ts";
import { enabledFamilies, type ToolkitFamilySelection, type ToolkitManagedToolset, type ToolkitToolDefinition } from "./common.ts";

export interface CreateToolkitToolsOptions extends ToolkitRuntimeOptions {
  runtime?: ToolkitRuntimeContext;
  families?: ToolkitFamilySelection;
}

export interface ToolkitAggregateToolset {
  runtime: ToolkitRuntimeContext;
  tools: ToolkitToolDefinition[];
  shutdown: (graceful?: boolean) => Promise<void>;
  dispose: () => Promise<void>;
}

export function createToolkitTools(options: CreateToolkitToolsOptions = {}): ToolkitAggregateToolset {
  const runtime = options.runtime ?? createToolkitRuntimeContext(options);
  const families = enabledFamilies(options.families);
  const tools: ToolkitToolDefinition[] = [];
  const managed: ToolkitManagedToolset[] = [];

  if (families.lean) {
    const lean = createAftkLeanTools({ ...(options as CreateAftkLeanToolsOptions), runtime });
    tools.push(...lean.tools);
    managed.push(lean);
  }

  if (families.knowledgebase) {
    const knowledgebase = createKnowledgeBaseTools({ ...(options as CreateKnowledgeBaseToolsOptions), runtime });
    tools.push(...knowledgebase.tools);
  }

  if (families.informal) {
    const informal = createInformalTools({ ...(options as CreateInformalToolsOptions), runtime });
    tools.push(...informal.tools);
  }

  const shutdown = async (graceful = true): Promise<void> => {
    for (const toolset of managed) {
      await toolset.shutdown(graceful);
    }
  };

  return {
    runtime,
    tools,
    shutdown,
    dispose: async () => {
      await shutdown(true);
    },
  };
}
