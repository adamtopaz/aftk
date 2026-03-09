import {
  AftkServerClient,
  AftkServerRpcError,
  type CreateAftkServerClientOptions,
} from "../server/client.ts";
import {
  AftkServerErrorCode,
  classifyAftkServerErrorCode,
  type HoverResult,
  type InfoViewResult,
  type LoadNodeResult,
  type PlainGoalResult,
  type PlainTermGoalResult,
  type RunTacticStepsResult,
  type SourceRange,
} from "../server/protocol.ts";
import {
  buildFailureResult,
  buildSuccessResult,
  diagnosticsFromRuntimeLike,
  toolErrorFromUnknown,
  type ToolkitBackendInfo,
  type ToolkitDiagnostics,
  type ToolkitToolError,
} from "../output/result.ts";
import { joinSections, renderGoals, renderRange, renderSection } from "../output/render.ts";
import {
  Schema,
  ToolInputError,
  normalizeToolPath,
  optionalString,
  requireNonEmptyString,
  requirePositiveInteger,
  requireString,
  requireStringArray,
  type ToolkitManagedToolset,
  type ToolkitToolDefinition,
} from "./common.ts";

export interface CreateAftkLeanToolsOptions extends CreateAftkServerClientOptions {
  client?: AftkServerClient;
}

const pathSchema = Schema.string("Path to the Lean source file.");
const lineSchema = Schema.integer("1-based line number.", { minimum: 1 });
const colSchema = Schema.integer("1-based column number.", { minimum: 1 });
const idSchema = Schema.string("Opaque node id returned by aftk_load_node.");
const tacticSchema = Schema.string("Lean tactic to execute.", { minLength: 1 });
const tacticsSchema = Schema.array(Schema.string("Lean tactic to execute.", { minLength: 1 }), "Ordered list of tactics.", {
  minItems: 1,
});

const OpenParams = Schema.object({ path: pathSchema }, ["path"]);
const CloseParams = Schema.object({ path: pathSchema }, ["path"]);
const LocationParams = Schema.object({ path: pathSchema, line: lineSchema, col: colSchema }, ["path", "line", "col"]);
const GetGoalsParams = Schema.object({ path: pathSchema, id: idSchema }, ["path", "id"]);
const RunTacticParams = Schema.object({ path: pathSchema, id: idSchema, tactic: tacticSchema }, ["path", "id", "tactic"]);
const RunTacticStepsParams = Schema.object({ path: pathSchema, id: idSchema, tactics: tacticsSchema }, ["path", "id", "tactics"]);
const EmptyParams = Schema.object({}, []);

function renderHover(result: HoverResult | null): string {
  if (result === null) {
    return "No hover information at this location.";
  }
  return `${result.text}${renderRange(result.range)}`;
}

function renderPlainGoal(result: PlainGoalResult | null): string {
  if (result === null) {
    return "No goal information at this location.";
  }
  if (result.rendered.trim().length > 0) {
    return result.rendered;
  }
  return renderGoals(result.goals);
}

function renderPlainTermGoal(result: PlainTermGoalResult | null): string {
  if (result === null) {
    return "No term goal information at this location.";
  }
  return `${result.goal}${renderRange(result.range)}`;
}

function renderInfoView(result: InfoViewResult): string {
  return joinSections([
    renderSection("Hover", renderHover(result.hover ?? null)),
    renderSection("Goal", renderPlainGoal(result.plainGoal ?? null)),
    renderSection("Term goal", renderPlainTermGoal(result.plainTermGoal ?? null)),
  ]);
}

function renderLoadNode(result: LoadNodeResult): string {
  if (result.id.length === 0) {
    return "No tactic nodes found at this location.";
  }
  if (result.id.length === 1) {
    return `Node id: ${result.id[0]}`;
  }
  return [
    `Loaded ${result.id.length} node ids:`,
    ...result.id.map((id, index) => `${index + 1}. ${id}`),
  ].join("\n");
}

function renderRangeSuffix(value: string | undefined): string {
  return value === undefined || value.length === 0 ? "" : ` (${value})`;
}

function leanRpcErrorText(error: AftkServerRpcError): string {
  const data = typeof error.data === "string" ? error.data : undefined;
  switch (error.code) {
    case AftkServerErrorCode.FileNotOpen:
      return `File is not open. Use aftk_open first.${renderRangeSuffix(data)}`;
    case AftkServerErrorCode.FileChanged:
      return `File changed; reopen required.${renderRangeSuffix(data)}`;
    case AftkServerErrorCode.WorkerUnavailable:
      return `File worker is unavailable. Reopen the file and try again.${renderRangeSuffix(data)}`;
    case AftkServerErrorCode.StaleNode:
      return `Stale or unknown node id. Load a fresh node and try again.${renderRangeSuffix(data)}`;
    case AftkServerErrorCode.TacticFailed:
      return data === undefined || data.length === 0 ? "Tactic failed." : `Tactic failed.\n\n${data}`;
    default:
      return `AFTK hub RPC error: ${error.message}`;
  }
}

function leanRpcToolError(error: AftkServerRpcError): ToolkitToolError {
  return {
    kind: "rpc",
    category: classifyAftkServerErrorCode(error.code),
    message: error.message,
    code: error.code,
    data: error.data,
  };
}

function failureResult(tool: string, method: string, error: unknown): ReturnType<typeof buildFailureResult> {
  const backend: ToolkitBackendInfo = { kind: "server", method };
  if (error instanceof ToolInputError) {
    return buildFailureResult({
      tool,
      family: "lean",
      backend,
      text: error.message,
      error: {
        kind: "runtime",
        category: "usage",
        message: error.message,
        code: error.code,
      },
    });
  }
  if (error instanceof AftkServerRpcError) {
    return buildFailureResult({
      tool,
      family: "lean",
      backend,
      text: leanRpcErrorText(error),
      error: leanRpcToolError(error),
      diagnostics: error.diagnostics,
    });
  }
  return buildFailureResult({
    tool,
    family: "lean",
    backend,
    text: toolErrorFromUnknown(error).message,
    error: toolErrorFromUnknown(error),
    diagnostics: diagnosticsFromRuntimeLike(error) as ToolkitDiagnostics | undefined,
  });
}

function locationParams(params: unknown): { path: string; line: number; col: number } {
  return {
    path: normalizeToolPath(requireString(params, "path")),
    line: requirePositiveInteger(params, "line"),
    col: requirePositiveInteger(params, "col"),
  };
}

function fileNodeParams(params: unknown): { path: string; id: string } {
  return {
    path: normalizeToolPath(requireString(params, "path")),
    id: requireNonEmptyString(params, "id"),
  };
}

export function createAftkLeanTools(options: CreateAftkLeanToolsOptions = {}): ToolkitManagedToolset & { client: AftkServerClient } {
  const client = options.client ?? new AftkServerClient(options);

  const tools: ToolkitToolDefinition[] = [
    {
      name: "aftk_open",
      label: "AFTK Open",
      description: "Open a Lean file in the AFTK hub server.",
      parameters: OpenParams,
      async execute(_toolCallId, params, signal) {
        const tool = "aftk_open";
        try {
          const path = normalizeToolPath(requireString(params, "path"));
          const result = await client.open({ path }, { signal });
          return buildSuccessResult({
            tool,
            family: "lean",
            backend: { kind: "server", method: "open" },
            text: result.opened ? `Opened file worker: ${result.path}` : `File already open: ${result.path}`,
            result,
          });
        } catch (error) {
          return failureResult(tool, "open", error);
        }
      },
    },
    {
      name: "aftk_close",
      label: "AFTK Close",
      description: "Close a Lean file in the AFTK hub server.",
      parameters: CloseParams,
      async execute(_toolCallId, params, signal) {
        const tool = "aftk_close";
        try {
          const path = normalizeToolPath(requireString(params, "path"));
          const result = await client.close({ path }, { signal });
          return buildSuccessResult({
            tool,
            family: "lean",
            backend: { kind: "server", method: "close" },
            text: result.closed ? `Closed file worker: ${result.path}` : `File was not open: ${result.path}`,
            result,
          });
        } catch (error) {
          return failureResult(tool, "close", error);
        }
      },
    },
    {
      name: "aftk_load_node",
      label: "AFTK Load Node",
      description: "Resolve a source location to one or more tactic node ids.",
      parameters: LocationParams,
      async execute(_toolCallId, params, signal) {
        const tool = "aftk_load_node";
        try {
          const result = await client.loadNode(locationParams(params), { signal });
          return buildSuccessResult({
            tool,
            family: "lean",
            backend: { kind: "server", method: "load_node" },
            text: renderLoadNode(result),
            result,
          });
        } catch (error) {
          return failureResult(tool, "load_node", error);
        }
      },
    },
    {
      name: "aftk_get_hover",
      label: "AFTK Get Hover",
      description: "Fetch hover information at a source location.",
      parameters: LocationParams,
      async execute(_toolCallId, params, signal) {
        const tool = "aftk_get_hover";
        try {
          const result = await client.getHover(locationParams(params), { signal });
          return buildSuccessResult({
            tool,
            family: "lean",
            backend: { kind: "server", method: "get_hover" },
            text: renderHover(result),
            result,
          });
        } catch (error) {
          return failureResult(tool, "get_hover", error);
        }
      },
    },
    {
      name: "aftk_get_plain_goal",
      label: "AFTK Get Plain Goal",
      description: "Fetch plain pretty-printed tactic goals at a source location.",
      parameters: LocationParams,
      async execute(_toolCallId, params, signal) {
        const tool = "aftk_get_plain_goal";
        try {
          const result = await client.getPlainGoal(locationParams(params), { signal });
          return buildSuccessResult({
            tool,
            family: "lean",
            backend: { kind: "server", method: "get_plain_goal" },
            text: renderPlainGoal(result),
            result,
          });
        } catch (error) {
          return failureResult(tool, "get_plain_goal", error);
        }
      },
    },
    {
      name: "aftk_get_plain_term_goal",
      label: "AFTK Get Plain Term Goal",
      description: "Fetch the expected type or term goal at a source location.",
      parameters: LocationParams,
      async execute(_toolCallId, params, signal) {
        const tool = "aftk_get_plain_term_goal";
        try {
          const result = await client.getPlainTermGoal(locationParams(params), { signal });
          return buildSuccessResult({
            tool,
            family: "lean",
            backend: { kind: "server", method: "get_plain_term_goal" },
            text: renderPlainTermGoal(result),
            result,
          });
        } catch (error) {
          return failureResult(tool, "get_plain_term_goal", error);
        }
      },
    },
    {
      name: "aftk_get_infoview",
      label: "AFTK Get Infoview",
      description: "Fetch hover, goal, and term-goal info at a source location.",
      parameters: LocationParams,
      async execute(_toolCallId, params, signal) {
        const tool = "aftk_get_infoview";
        try {
          const result = await client.getInfoView(locationParams(params), { signal });
          return buildSuccessResult({
            tool,
            family: "lean",
            backend: { kind: "server", method: "get_infoview" },
            text: renderInfoView(result),
            result,
          });
        } catch (error) {
          return failureResult(tool, "get_infoview", error);
        }
      },
    },
    {
      name: "aftk_get_goals",
      label: "AFTK Get Goals",
      description: "Fetch the goals for a previously loaded node id.",
      parameters: GetGoalsParams,
      async execute(_toolCallId, params, signal) {
        const tool = "aftk_get_goals";
        try {
          const result = await client.getGoals(fileNodeParams(params), { signal });
          return buildSuccessResult({
            tool,
            family: "lean",
            backend: { kind: "server", method: "get_goals" },
            text: renderGoals(result.goals),
            result,
          });
        } catch (error) {
          return failureResult(tool, "get_goals", error);
        }
      },
    },
    {
      name: "aftk_run_tactic",
      label: "AFTK Run Tactic",
      description: "Run one tactic from a previously loaded node id.",
      parameters: RunTacticParams,
      async execute(_toolCallId, params, signal) {
        const tool = "aftk_run_tactic";
        try {
          const path = normalizeToolPath(requireString(params, "path"));
          const id = requireNonEmptyString(params, "id");
          const tactic = requireNonEmptyString(params, "tactic");
          const result = await client.runTactic({ path, id, tactic }, { signal });
          return buildSuccessResult({
            tool,
            family: "lean",
            backend: { kind: "server", method: "run_tactic" },
            text: [`nextId: ${result.nextId}`, "", renderGoals(result.goals)].join("\n"),
            result,
          });
        } catch (error) {
          return failureResult(tool, "run_tactic", error);
        }
      },
    },
    {
      name: "aftk_run_tactic_steps",
      label: "AFTK Run Tactic Steps",
      description: "Run a sequence of tactics from a previously loaded node id.",
      parameters: RunTacticStepsParams,
      async execute(_toolCallId, params, signal) {
        const tool = "aftk_run_tactic_steps";
        try {
          const path = normalizeToolPath(requireString(params, "path"));
          const id = requireNonEmptyString(params, "id");
          const tactics = requireStringArray(params, "tactics", { nonEmpty: true, itemNonEmpty: true });
          const result = await client.runTacticSteps({ path, id, tactics }, { signal });
          const text = renderRunTacticSteps(result);
          return buildSuccessResult({
            tool,
            family: "lean",
            backend: { kind: "server", method: "run_tactic_steps" },
            text,
            result,
          });
        } catch (error) {
          return failureResult(tool, "run_tactic_steps", error);
        }
      },
    },
    {
      name: "aftk_shutdown",
      label: "AFTK Shutdown",
      description: "Shutdown the AFTK hub and stop all managed file workers.",
      parameters: EmptyParams,
      async execute() {
        const tool = "aftk_shutdown";
        try {
          const result = await client.shutdown();
          return buildSuccessResult({
            tool,
            family: "lean",
            backend: { kind: "server", method: "shutdown" },
            text: `Stopped ${result.stopped} file worker(s).`,
            result,
          });
        } catch (error) {
          return failureResult(tool, "shutdown", error);
        }
      },
    },
  ];

  return {
    tools,
    client,
    shutdown: async (graceful = true) => {
      await client.stop(graceful);
    },
  };
}

function renderRunTacticSteps(result: RunTacticStepsResult): string {
  if (result.results.length === 0) {
    return "No step results returned.";
  }
  return result.results
    .map((step, index) => {
      const header = `Step ${index + 1} nextId: ${step.nextId}`;
      return `${header}\n${"-".repeat(header.length)}\n${renderGoals(step.goals)}`;
    })
    .join("\n\n");
}

export function createAFTKTools(options: CreateAftkLeanToolsOptions = {}): ToolkitManagedToolset {
  return createAftkLeanTools(options);
}
