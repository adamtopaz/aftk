import {
  InformalClient,
  type CreateInformalClientOptions,
  type InformalCliFailure,
  type InformalCliResponse,
  type InformalBodyPresentation,
  type InformalDeclEntry,
  type InformalPresentationPayload,
  type InformalPresentationSummary,
  type InformalReferenceEntry,
} from "../informal/client.ts";
import {
  buildFailureResult,
  buildSuccessResult,
  cliCategoryFromExitCode,
  diagnosticsFromRuntimeLike,
  toolErrorFromUnknown,
  type ToolkitBackendInfo,
  type ToolkitToolError,
} from "../output/result.ts";
import {
  Schema,
  ToolInputError,
  optionalBoolean,
  optionalEnum,
  optionalString,
  requireNonEmptyString,
  requireStringArray,
  type ToolkitStatelessToolset,
  type ToolkitToolDefinition,
} from "./common.ts";

export interface CreateInformalToolsOptions extends CreateInformalClientOptions {
  client?: InformalClient;
}

const presentModes = ["compact", "rich"] as const;
const bodyModes = ["none", "preview", "full"] as const;
const depsModes = ["decl", "ref"] as const;

const modulesParam = Schema.array(Schema.string("Lean module name.", { minLength: 1 }), "Imported module names.", { minItems: 1 });
const rootParam = Schema.string("Optional knowledge-base root.");

const EnvironmentParams = Schema.object({ modules: modulesParam }, ["modules"]);
const DeclsParams = Schema.object(
  {
    modules: modulesParam,
    prefix: Schema.string("Optional declaration-name prefix."),
    ref: Schema.string("Optional node id filter."),
  },
  ["modules"],
);
const RefsParams = Schema.object(
  {
    modules: modulesParam,
    prefix: Schema.string("Optional node-id prefix."),
  },
  ["modules"],
);
const DepsParams = Schema.object(
  {
    modules: modulesParam,
    mode: Schema.enum(depsModes, "Dependency view mode."),
    onlyLeaves: Schema.boolean("Restrict rows to leaves only."),
  },
  ["modules"],
);
const PresentParams = Schema.object(
  {
    ref: Schema.string("Informal node id."),
    root: rootParam,
    mode: Schema.enum(presentModes, "Presentation mode."),
    body: Schema.enum(bodyModes, "Rich-mode body rendering policy."),
  },
  ["ref"],
);

function backend(command: string, modules: string[] | undefined, root: string | undefined, exitCode: number | undefined): ToolkitBackendInfo {
  return {
    kind: "informal_cli",
    command,
    modules,
    root,
    exitCode,
  };
}

function renderDeclEntryLine(entry: InformalDeclEntry): string {
  const refs = entry.refs.length === 0 ? "(none)" : entry.refs.join(", ");
  return `- ${entry.declName} [${entry.refCount}]: ${refs}`;
}

function renderRefEntryLine(entry: InformalReferenceEntry): string {
  const decls = entry.declNames.length === 0 ? "(none)" : entry.declNames.join(", ");
  return `- ${entry.ref} [${entry.declCount}]: ${decls}`;
}

function renderSummary(summary: InformalPresentationSummary): string {
  const lines = [`Informal node: ${summary.ref}`, `Title: ${summary.title}`];
  if (summary.kind !== undefined) lines.push(`Kind: ${summary.kind}`);
  if (summary.status !== undefined) lines.push(`Status: ${summary.status}`);
  if (summary.summary !== undefined) lines.push(`Summary: ${summary.summary}`);
  return lines.join("\n");
}

function renderBody(body: InformalBodyPresentation): string[] {
  switch (body.kind) {
    case "none":
      return [];
    case "full":
      return ["", "Body", "----", ...body.text.split(/\r?\n/)];
    case "preview": {
      const trailer = body.truncated ? ["", "[truncated]"] : [];
      return ["", "Body", "----", ...body.text.split(/\r?\n/), ...trailer];
    }
  }
}

function renderPayload(payload: InformalPresentationPayload): string {
  const lines = [renderSummary(payload.summary)];
  if (payload.tags.length > 0) lines.push("", "Tags", "----", ...payload.tags.map((tag) => `- ${tag}`));
  if (payload.authors.length > 0) lines.push("", "Authors", "-------", ...payload.authors.map((author) => `- ${author}`));
  if (payload.relationshipLines.length > 0)
    lines.push("", "Relationships", "-------------", ...payload.relationshipLines.map((line) => `- ${line}`));
  if (payload.leanRefLines.length > 0)
    lines.push("", "Lean refs", "---------", ...payload.leanRefLines.map((line) => `- ${line}`));
  lines.push(...renderBody(payload.body));
  return lines.join("\n");
}

function cliFailureText(failure: InformalCliFailure): string {
  if (failure.error.code === "informal.notTracked") {
    return failure.error.message;
  }
  switch (cliCategoryFromExitCode(failure.error.exitCode)) {
    case "usage":
      return `Informal command usage error.\n\n${failure.error.message}`;
    case "not_found":
      return failure.error.message;
    case "validation":
      return `Informal presentation failed because the underlying knowledge-base data is invalid.\n\n${failure.error.message}`;
    default:
      return failure.error.message;
  }
}

function cliFailureError(failure: InformalCliFailure): ToolkitToolError {
  const category =
    failure.error.code === "informal.notTracked"
      ? "not_tracked"
      : failure.command === "present" && cliCategoryFromExitCode(failure.error.exitCode) === "not_found"
        ? "not_found"
        : cliCategoryFromExitCode(failure.error.exitCode);
  return {
    kind: "cli",
    category,
    message: failure.error.message,
    code: failure.error.code ?? failure.error.exitCode,
    data: { exitCode: failure.error.exitCode },
  };
}

function runtimeFailure(tool: string, command: string, error: unknown): ReturnType<typeof buildFailureResult> {
  if (error instanceof ToolInputError) {
    return buildFailureResult({
      tool,
      family: "informal",
      backend: backend(command, undefined, undefined, undefined),
      text: error.message,
      error: {
        kind: "runtime",
        category: "usage",
        message: error.message,
        code: error.code,
      },
    });
  }
  const normalized = toolErrorFromUnknown(error);
  return buildFailureResult({
    tool,
    family: "informal",
    backend: backend(command, undefined, undefined, undefined),
    text: normalized.message,
    error: normalized,
    diagnostics: diagnosticsFromRuntimeLike(error),
  });
}

function renderFailure(tool: string, root: string | undefined, failure: InformalCliFailure): ReturnType<typeof buildFailureResult> {
  return buildFailureResult({
    tool,
    family: "informal",
    backend: backend(failure.command ?? "unknown", undefined, root, failure.error.exitCode),
    text: cliFailureText(failure),
    error: cliFailureError(failure),
    diagnostics: failure.diagnostics,
  });
}

function modules(params: unknown): string[] {
  return requireStringArray(params, "modules", { nonEmpty: true, itemNonEmpty: true });
}

export function createInformalTools(options: CreateInformalToolsOptions = {}): ToolkitStatelessToolset & { client: InformalClient } {
  const client = options.client ?? new InformalClient(options);

  const tools: ToolkitToolDefinition[] = [
    {
      name: "informal_status",
      label: "Informal Status",
      description: "Show high-level counts for tracked declarations and references.",
      parameters: EnvironmentParams,
      async execute(_toolCallId, params, signal) {
        const tool = "informal_status";
        try {
          const response = await client.status({ modules: modules(params), signal });
          if (!response.ok) return renderFailure(tool, undefined, response);
          return buildSuccessResult({
            tool,
            family: "informal",
            backend: backend(response.command, response.modules, undefined, response.diagnostics.exitCode ?? undefined),
            text: [
              `Tracked declarations: ${response.result.trackedDeclarations}`,
              `Tracked references: ${response.result.trackedReferences}`,
              `Declarations with multiple references: ${response.result.declarationsWithMultipleReferences}`,
            ].join("\n"),
            result: response.result,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "status", error);
        }
      },
    },
    {
      name: "informal_decls",
      label: "Informal Decls",
      description: "List tracked declarations and the node ids they reference.",
      parameters: DeclsParams,
      async execute(_toolCallId, params, signal) {
        const tool = "informal_decls";
        try {
          const response = await client.decls({
            modules: modules(params),
            prefix: optionalString(params, "prefix"),
            ref: optionalString(params, "ref"),
            signal,
          });
          if (!response.ok) return renderFailure(tool, undefined, response);
          const text =
            response.result.entries.length === 0
              ? "Tracked declarations (0)"
              : [
                  `Tracked declarations (${response.result.count})`,
                  ...response.result.entries.map(renderDeclEntryLine),
                ].join("\n");
          return buildSuccessResult({
            tool,
            family: "informal",
            backend: backend(response.command, response.modules, undefined, response.diagnostics.exitCode ?? undefined),
            text,
            result: response.result,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "decls", error);
        }
      },
    },
    {
      name: "informal_decl",
      label: "Informal Decl",
      description: "Show one tracked declaration and its referenced node ids.",
      parameters: Schema.object({ modules: modulesParam, declName: Schema.string("Declaration name.") }, ["modules", "declName"]),
      async execute(_toolCallId, params, signal) {
        const tool = "informal_decl";
        try {
          const declName = requireNonEmptyString(params, "declName");
          const response = await client.decl(declName, { modules: modules(params), signal });
          if (!response.ok) return renderFailure(tool, undefined, response);
          return buildSuccessResult({
            tool,
            family: "informal",
            backend: backend(response.command, response.modules, undefined, response.diagnostics.exitCode ?? undefined),
            text: [
              `Declaration: ${response.result.entry.declName}`,
              `Reference count: ${response.result.entry.refCount}`,
              `References: ${response.result.entry.refs.length === 0 ? "(none)" : response.result.entry.refs.join(", ")}`,
            ].join("\n"),
            result: response.result,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "decl", error);
        }
      },
    },
    {
      name: "informal_refs",
      label: "Informal Refs",
      description: "List tracked references and the declarations that reference them.",
      parameters: RefsParams,
      async execute(_toolCallId, params, signal) {
        const tool = "informal_refs";
        try {
          const response = await client.refs({
            modules: modules(params),
            prefix: optionalString(params, "prefix"),
            signal,
          });
          if (!response.ok) return renderFailure(tool, undefined, response);
          const text =
            response.result.entries.length === 0
              ? "Tracked references (0)"
              : [
                  `Tracked references (${response.result.count})`,
                  ...response.result.entries.map(renderRefEntryLine),
                ].join("\n");
          return buildSuccessResult({
            tool,
            family: "informal",
            backend: backend(response.command, response.modules, undefined, response.diagnostics.exitCode ?? undefined),
            text,
            result: response.result,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "refs", error);
        }
      },
    },
    {
      name: "informal_ref",
      label: "Informal Ref",
      description: "Show one tracked reference and the declarations that reference it.",
      parameters: Schema.object({ modules: modulesParam, ref: Schema.string("Informal node id.") }, ["modules", "ref"]),
      async execute(_toolCallId, params, signal) {
        const tool = "informal_ref";
        try {
          const ref = requireNonEmptyString(params, "ref");
          const response = await client.ref(ref, { modules: modules(params), signal });
          if (!response.ok) return renderFailure(tool, undefined, response);
          return buildSuccessResult({
            tool,
            family: "informal",
            backend: backend(response.command, response.modules, undefined, response.diagnostics.exitCode ?? undefined),
            text: [
              `Reference: ${response.result.entry.ref}`,
              `Declaration count: ${response.result.entry.declCount}`,
              `Declarations: ${response.result.entry.declNames.length === 0 ? "(none)" : response.result.entry.declNames.join(", ")}`,
            ].join("\n"),
            result: response.result,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "ref", error);
        }
      },
    },
    {
      name: "informal_deps",
      label: "Informal Deps",
      description: "Show declaration or reference dependency views.",
      parameters: DepsParams,
      async execute(_toolCallId, params, signal) {
        const tool = "informal_deps";
        try {
          const mode = optionalEnum(params, "mode", depsModes) ?? "decl";
          const onlyLeaves = optionalBoolean(params, "onlyLeaves") ?? false;
          const response = await client.deps({ modules: modules(params), mode, onlyLeaves, signal });
          if (!response.ok) return renderFailure(tool, undefined, response);
          return buildSuccessResult({
            tool,
            family: "informal",
            backend: backend(response.command, response.modules, undefined, response.diagnostics.exitCode ?? undefined),
            text: renderDeps(response.result),
            result: response.result,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "deps", error);
        }
      },
    },
    {
      name: "informal_present",
      label: "Informal Present",
      description: "Render direct knowledge-base-backed presentation for one node id.",
      parameters: PresentParams,
      async execute(_toolCallId, params, signal) {
        const tool = "informal_present";
        try {
          const ref = requireNonEmptyString(params, "ref");
          const root = optionalString(params, "root");
          const mode = optionalEnum(params, "mode", presentModes) ?? "rich";
          const body = optionalEnum(params, "body", bodyModes);
          if (mode === "compact" && body !== undefined) {
            throw new ToolInputError(`Parameter 'body' may not be used when mode is 'compact'.`);
          }
          const response = await client.present(ref, { root, mode, body, signal });
          if (!response.ok) return renderFailure(tool, root, response);
          return buildSuccessResult({
            tool,
            family: "informal",
            backend: backend(response.command, response.modules, root, response.diagnostics.exitCode ?? undefined),
            text: response.result.mode === "compact" ? renderSummary(response.result.summary) : renderPayload(response.result.payload),
            result: response.result,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "present", error);
        }
      },
    },
  ];

  return { tools, client };
}

function renderDeps(
  result:
    | {
        modules: string[];
        mode: "decl";
        onlyLeaves: boolean;
        rows: Array<{ declName: string; dependencies: string[] }>;
        leaves: string[];
      }
    | {
        modules: string[];
        mode: "ref";
        onlyLeaves: boolean;
        rows: Array<{ ref: string; dependencies: string[] }>;
        leaves: string[];
      },
): string {
  if (result.mode === "decl") {
    const leafLines = result.leaves.length === 0 ? ["- (none)"] : result.leaves.map((leaf) => `- ${leaf}`);
    return [
      `Declaration dependencies (${result.rows.length})`,
      ...result.rows.map((row) => `- ${row.declName} -> ${row.dependencies.length === 0 ? "(none)" : row.dependencies.join(", ")}`),
      "",
      `Leaves (${result.leaves.length})`,
      ...leafLines,
    ].join("\n");
  }
  const leafLines = result.leaves.length === 0 ? ["- (none)"] : result.leaves.map((leaf) => `- ${leaf}`);
  return [
    `Reference dependencies (${result.rows.length})`,
    ...result.rows.map((row) => `- ${row.ref} -> ${row.dependencies.length === 0 ? "(none)" : row.dependencies.join(", ")}`),
    "",
    `Leaves (${result.leaves.length})`,
    ...leafLines,
  ].join("\n");
}
