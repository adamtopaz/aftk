import {
  KnowledgeBaseClient,
  type CreateKnowledgeBaseClientOptions,
  type IncomingRelationship,
  type KnowledgeBaseCliFailure,
  type KnowledgeBaseCliResponse,
  type KnowledgeBaseRelationshipsMode,
  type KnowledgeBaseShowView,
  type NodeKind,
  type NodeMetadata,
  type NodePaths,
  type NodeStatus,
  type Relationship,
  type SearchHit,
  type StoredNode,
  type ValidationReport,
} from "../knowledgebase/client.ts";
import {
  buildFailureResult,
  buildSuccessResult,
  cliCategoryFromExitCode,
  diagnosticsFromRuntimeLike,
  toolErrorFromUnknown,
  type ToolkitBackendInfo,
  type ToolkitToolError,
} from "../output/result.ts";
import { Schema, ToolInputError, optionalEnum, optionalString, requireNonEmptyString, requirePositiveInteger, type ToolkitStatelessToolset, type ToolkitToolDefinition } from "./common.ts";

export interface CreateKnowledgeBaseToolsOptions extends CreateKnowledgeBaseClientOptions {
  client?: KnowledgeBaseClient;
}

const nodeKinds = [
  "note",
  "definition",
  "theorem",
  "proofSketch",
  "example",
  "explanation",
  "concept",
  "documentation",
] as const satisfies readonly NodeKind[];

const nodeStatuses = ["draft", "active", "deprecated", "archived"] as const satisfies readonly NodeStatus[];
const showViews = ["combined", "body", "metadata", "paths"] as const satisfies readonly KnowledgeBaseShowView[];
const relationshipModes = ["outgoing", "incoming", "related"] as const satisfies readonly KnowledgeBaseRelationshipsMode[];

const rootParam = Schema.string("Optional knowledge-base root.");
const idParam = Schema.string("Knowledge-base node id.");
const prefixParam = Schema.string("Optional dotted node-id prefix filter.");
const tagParam = Schema.string("Optional tag filter.");
const limitParam = Schema.integer("Optional positive result limit.", { minimum: 1 });

const StatusParams = Schema.object({ root: rootParam }, []);
const ListParams = Schema.object(
  {
    root: rootParam,
    prefix: prefixParam,
    kind: Schema.enum(nodeKinds, "Optional node kind filter."),
    status: Schema.enum(nodeStatuses, "Optional node status filter."),
    tag: tagParam,
  },
  [],
);
const ShowParams = Schema.object(
  {
    root: rootParam,
    id: idParam,
    view: Schema.enum(showViews, "Which node view to show."),
  },
  ["id"],
);
const SearchTextParams = Schema.object(
  {
    root: rootParam,
    query: Schema.string("Search query."),
    limit: limitParam,
  },
  ["query"],
);
const SearchTagParams = Schema.object(
  {
    root: rootParam,
    tag: Schema.string("Exact tag to search for."),
    limit: limitParam,
  },
  ["tag"],
);
const RelationshipsParams = Schema.object(
  {
    root: rootParam,
    id: idParam,
    mode: Schema.enum(relationshipModes, "Relationship direction to inspect."),
  },
  ["id", "mode"],
);
const ValidateNodeParams = Schema.object({ root: rootParam, id: idParam }, ["id"]);

function countValidationIssues(report: ValidationReport): { errors: number; warnings: number; infos: number } {
  let errors = 0;
  let warnings = 0;
  let infos = 0;
  for (const issue of report.issues) {
    switch (issue.severity) {
      case "error":
        errors += 1;
        break;
      case "warning":
        warnings += 1;
        break;
      case "info":
        infos += 1;
        break;
    }
  }
  return { errors, warnings, infos };
}

function renderMetadataSummary(metadata: NodeMetadata): string {
  const lines = [
    `Node: ${metadata.id}`,
    `Title: ${metadata.title}`,
    `Kind: ${metadata.kind}`,
    `Status: ${metadata.status}`,
  ];
  if (metadata.summary !== undefined) lines.push(`Summary: ${metadata.summary}`);
  if (metadata.tags.length > 0) lines.push(`Tags: ${metadata.tags.join(", ")}`);
  if (metadata.authors.length > 0) lines.push(`Authors: ${metadata.authors.join(", ")}`);
  return lines.join("\n");
}

function renderStoredNode(stored: StoredNode): string {
  return [
    renderMetadataSummary(stored.node.metadata),
    `MarkdownPath: ${stored.paths.markdownPath}`,
    `MetadataPath: ${stored.paths.metadataPath}`,
    "",
    "Body",
    "----",
    stored.node.body,
  ].join("\n");
}

function renderPaths(paths: NodePaths): string {
  return [`MarkdownPath: ${paths.markdownPath}`, `MetadataPath: ${paths.metadataPath}`].join("\n");
}

function renderSearchHits(label: string, hits: SearchHit[]): string {
  if (hits.length === 0) {
    return `No ${label} hits.`;
  }
  const blocks = hits.map((hit) => {
    const title = hit.title === undefined ? hit.id : `${hit.id} — ${hit.title}`;
    const summary = hit.summary === undefined ? [] : [hit.summary];
    const snippet = hit.snippet === undefined ? [] : [hit.snippet];
    return [title, ...summary, ...snippet].join("\n");
  });
  return [`${label} hits: ${hits.length}`, ...blocks.map((block) => `- ${block.replace(/\n/g, "\n  ")}`)].join("\n");
}

function renderOutgoingRelationships(id: string, relationships: Relationship[]): string {
  if (relationships.length === 0) {
    return "No outgoing relationships.";
  }
  return [
    `Outgoing relationships (${relationships.length})`,
    ...relationships.map((relationship) => {
      const label = relationship.label === undefined ? "" : ` — ${relationship.label}`;
      return `- ${relationship.kind}: ${relationship.target}${label}`;
    }),
  ].join("\n");
}

function renderIncomingRelationships(id: string, relationships: IncomingRelationship[]): string {
  if (relationships.length === 0) {
    return "No incoming relationships.";
  }
  return [
    `Incoming relationships (${relationships.length})`,
    ...relationships.map((relationship) => {
      const title = relationship.sourceTitle === undefined ? "" : ` (${relationship.sourceTitle})`;
      return `- ${relationship.source}${title}: ${relationship.relationship.kind}`;
    }),
  ].join("\n");
}

function renderValidation(scopeLabel: string, report: ValidationReport): string {
  if (report.issues.length === 0) {
    return `${scopeLabel} validation passed.`;
  }
  const counts = countValidationIssues(report);
  const summary = `${scopeLabel} validation ${report.ok ? "completed" : "found issues"}: ${report.issues.length} issue(s), ${counts.errors} error(s), ${counts.warnings} warning(s), ${counts.infos} info item(s).`;
  const firstIssues = report.issues.slice(0, 5).map((issue) => `- ${issue.severity}: ${issue.code}: ${issue.message}`);
  return [summary, ...firstIssues].join("\n");
}

function cliFailureText(failure: KnowledgeBaseCliFailure): string {
  const code = failure.error.code;
  if (code === "node.notFound") {
    return failure.error.message;
  }
  if (code === "storage.rootNotInitialized") {
    return "Knowledge base root is not initialized.";
  }
  switch (cliCategoryFromExitCode(failure.exitCode)) {
    case "usage":
      return `Knowledge base command usage error.\n\n${failure.error.message}`;
    case "not_found":
      return failure.error.message;
    case "validation":
      return `Validation failed before a report could be produced.\n\n${failure.error.message}`;
    case "conflict":
      return failure.error.message;
    default:
      return failure.error.message;
  }
}

function cliFailureError(failure: KnowledgeBaseCliFailure): ToolkitToolError {
  return {
    kind: "cli",
    category: cliCategoryFromExitCode(failure.exitCode),
    message: failure.error.message,
    code: failure.error.code ?? failure.exitCode ?? undefined,
    data: { exitCode: failure.exitCode },
  };
}

function backend(command: string, root: string | undefined, exitCode: number | null | undefined): ToolkitBackendInfo {
  return {
    kind: "knowledgebase_cli",
    command,
    root,
    exitCode,
  };
}

function runtimeFailure(tool: string, command: string, error: unknown): ReturnType<typeof buildFailureResult> {
  if (error instanceof ToolInputError) {
    return buildFailureResult({
      tool,
      family: "knowledgebase",
      backend: backend(command, undefined, undefined),
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
    family: "knowledgebase",
    backend: backend(command, undefined, undefined),
    text: normalized.message,
    error: normalized,
    diagnostics: diagnosticsFromRuntimeLike(error),
  });
}

function rootOption(params: unknown): string | undefined {
  return optionalString(params, "root");
}

function positiveLimit(params: unknown): number | undefined {
  const record = params as Record<string, unknown>;
  if (record.limit === undefined) {
    return undefined;
  }
  return requirePositiveInteger(params, "limit");
}

function renderResponseFailure(tool: string, failure: KnowledgeBaseCliFailure): ReturnType<typeof buildFailureResult> {
  return buildFailureResult({
    tool,
    family: "knowledgebase",
    backend: backend(failure.command, failure.root, failure.exitCode),
    text: cliFailureText(failure),
    error: cliFailureError(failure),
    warnings: failure.warnings,
    diagnostics: failure.diagnostics,
  });
}

export function createKnowledgeBaseTools(
  options: CreateKnowledgeBaseToolsOptions = {},
): ToolkitStatelessToolset & { client: KnowledgeBaseClient } {
  const client = options.client ?? new KnowledgeBaseClient(options);

  const tools: ToolkitToolDefinition[] = [
    {
      name: "knowledgebase_status",
      label: "Knowledge Base Status",
      description: "Probe the resolved knowledge-base root and report initialization status.",
      parameters: StatusParams,
      async execute(_toolCallId, params, signal) {
        const tool = "knowledgebase_status";
        try {
          const response = await client.status({ root: rootOption(params), signal });
          if (!response.ok) return renderResponseFailure(tool, response);
          return buildSuccessResult({
            tool,
            family: "knowledgebase",
            backend: backend(response.command, response.root, response.exitCode),
            text: [
              `Knowledge base root: ${response.result.root}`,
              `Initialized: ${response.result.initialized ? "yes" : "no"}`,
              `Nodes: ${response.result.nodeCount}`,
            ].join("\n"),
            result: response.result,
            warnings: response.warnings,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "status", error);
        }
      },
    },
    {
      name: "knowledgebase_list",
      label: "Knowledge Base List",
      description: "List knowledge-base nodes with optional lightweight metadata filters.",
      parameters: ListParams,
      async execute(_toolCallId, params, signal) {
        const tool = "knowledgebase_list";
        try {
          const response = await client.list({
            root: rootOption(params),
            prefix: optionalString(params, "prefix"),
            kind: optionalEnum(params, "kind", nodeKinds),
            status: optionalEnum(params, "status", nodeStatuses),
            tag: optionalString(params, "tag"),
            signal,
          });
          if (!response.ok) return renderResponseFailure(tool, response);
          const text =
            response.result.items.length === 0
              ? "No nodes matched the requested filters."
              : [
                  `Nodes: ${response.result.count}`,
                  ...response.result.items.map((item) => `- ${item.id} | ${item.kind} | ${item.status} | ${item.title}`),
                ].join("\n");
          return buildSuccessResult({
            tool,
            family: "knowledgebase",
            backend: backend(response.command, response.root, response.exitCode),
            text,
            result: response.result,
            warnings: response.warnings,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "list", error);
        }
      },
    },
    {
      name: "knowledgebase_show",
      label: "Knowledge Base Show",
      description: "Inspect one knowledge-base node or one view of that node.",
      parameters: ShowParams,
      async execute(_toolCallId, params, signal) {
        const tool = "knowledgebase_show";
        try {
          const id = requireNonEmptyString(params, "id");
          const view = optionalEnum(params, "view", showViews) ?? "combined";
          const response = await client.show(id, { root: rootOption(params), view, signal });
          if (!response.ok) return renderResponseFailure(tool, response);
          const text = renderShowResult(response.result.value, response.result.view);
          return buildSuccessResult({
            tool,
            family: "knowledgebase",
            backend: backend(response.command, response.root, response.exitCode),
            text,
            result: response.result,
            warnings: response.warnings,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "show", error);
        }
      },
    },
    {
      name: "knowledgebase_search_text",
      label: "Knowledge Base Search Text",
      description: "Search knowledge-base body, title, and summary text.",
      parameters: SearchTextParams,
      async execute(_toolCallId, params, signal) {
        const tool = "knowledgebase_search_text";
        try {
          const query = requireNonEmptyString(params, "query");
          const response = await client.searchText(query, { root: rootOption(params), limit: positiveLimit(params), signal });
          if (!response.ok) return renderResponseFailure(tool, response);
          return buildSuccessResult({
            tool,
            family: "knowledgebase",
            backend: backend(response.command, response.root, response.exitCode),
            text: renderSearchHits("Text search", response.result.hits),
            result: response.result,
            warnings: response.warnings,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "search.text", error);
        }
      },
    },
    {
      name: "knowledgebase_search_tag",
      label: "Knowledge Base Search Tag",
      description: "Search knowledge-base nodes by exact tag.",
      parameters: SearchTagParams,
      async execute(_toolCallId, params, signal) {
        const tool = "knowledgebase_search_tag";
        try {
          const tag = requireNonEmptyString(params, "tag");
          const response = await client.searchTag(tag, { root: rootOption(params), limit: positiveLimit(params), signal });
          if (!response.ok) return renderResponseFailure(tool, response);
          return buildSuccessResult({
            tool,
            family: "knowledgebase",
            backend: backend(response.command, response.root, response.exitCode),
            text: renderSearchHits("Tag search", response.result.hits),
            result: response.result,
            warnings: response.warnings,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "search.tag", error);
        }
      },
    },
    {
      name: "knowledgebase_relationships",
      label: "Knowledge Base Relationships",
      description: "Inspect outgoing, incoming, or related relationships for one node.",
      parameters: RelationshipsParams,
      async execute(_toolCallId, params, signal) {
        const tool = "knowledgebase_relationships";
        try {
          const id = requireNonEmptyString(params, "id");
          const mode = optionalEnum(params, "mode", relationshipModes);
          if (mode === undefined) {
            throw new ToolInputError(`Parameter 'mode' is required.`);
          }
          const response = await client.relationships(id, mode, { root: rootOption(params), signal });
          if (!response.ok) return renderResponseFailure(tool, response);
          return buildSuccessResult({
            tool,
            family: "knowledgebase",
            backend: backend(response.command, response.root, response.exitCode),
            text: renderRelationships(response.result),
            result: response.result,
            warnings: response.warnings,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "relationships", error);
        }
      },
    },
    {
      name: "knowledgebase_validate_storage",
      label: "Knowledge Base Validate Storage",
      description: "Validate knowledge-base root and storage structure.",
      parameters: StatusParams,
      async execute(_toolCallId, params, signal) {
        const tool = "knowledgebase_validate_storage";
        try {
          const response = await client.validateStorage({ root: rootOption(params), signal });
          if (!response.ok) return renderResponseFailure(tool, response);
          return buildSuccessResult({
            tool,
            family: "knowledgebase",
            backend: backend(response.command, response.root, response.exitCode),
            text: renderValidation("Storage", response.result.report),
            result: response.result,
            warnings: response.warnings,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "validate.storage", error);
        }
      },
    },
    {
      name: "knowledgebase_validate_node",
      label: "Knowledge Base Validate Node",
      description: "Validate one knowledge-base node pair.",
      parameters: ValidateNodeParams,
      async execute(_toolCallId, params, signal) {
        const tool = "knowledgebase_validate_node";
        try {
          const id = requireNonEmptyString(params, "id");
          const response = await client.validateNode(id, { root: rootOption(params), signal });
          if (!response.ok) return renderResponseFailure(tool, response);
          return buildSuccessResult({
            tool,
            family: "knowledgebase",
            backend: backend(response.command, response.root, response.exitCode),
            text: renderValidation(`Node ${id}`, response.result.report),
            result: response.result,
            warnings: response.warnings,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "validate.node", error);
        }
      },
    },
    {
      name: "knowledgebase_validate_metadata",
      label: "Knowledge Base Validate Metadata",
      description: "Validate one knowledge-base node's metadata.",
      parameters: ValidateNodeParams,
      async execute(_toolCallId, params, signal) {
        const tool = "knowledgebase_validate_metadata";
        try {
          const id = requireNonEmptyString(params, "id");
          const response = await client.validateMetadata(id, { root: rootOption(params), signal });
          if (!response.ok) return renderResponseFailure(tool, response);
          return buildSuccessResult({
            tool,
            family: "knowledgebase",
            backend: backend(response.command, response.root, response.exitCode),
            text: renderValidation(`Metadata ${id}`, response.result.report),
            result: response.result,
            warnings: response.warnings,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "metadata.validate", error);
        }
      },
    },
    {
      name: "knowledgebase_validate_all",
      label: "Knowledge Base Validate All",
      description: "Run whole-root knowledge-base validation.",
      parameters: StatusParams,
      async execute(_toolCallId, params, signal) {
        const tool = "knowledgebase_validate_all";
        try {
          const response = await client.validateAll({ root: rootOption(params), signal });
          if (!response.ok) return renderResponseFailure(tool, response);
          return buildSuccessResult({
            tool,
            family: "knowledgebase",
            backend: backend(response.command, response.root, response.exitCode),
            text: renderValidation("Whole knowledge base", response.result.report),
            result: response.result,
            warnings: response.warnings,
            diagnostics: response.diagnostics,
          });
        } catch (error) {
          return runtimeFailure(tool, "validate.all", error);
        }
      },
    },
  ];

  return { tools, client };
}

function renderShowResult(value: StoredNode | string | NodeMetadata | NodePaths, view: KnowledgeBaseShowView): string {
  switch (view) {
    case "combined":
      return renderStoredNode(value as StoredNode);
    case "body":
      return value as string;
    case "metadata":
      return renderMetadataSummary(value as NodeMetadata);
    case "paths":
      return renderPaths(value as NodePaths);
  }
}

function renderRelationships(
  result:
    | { id: string; mode: "outgoing"; relationships: Relationship[] }
    | { id: string; mode: "incoming"; relationships: IncomingRelationship[] }
    | { id: string; mode: "related"; outgoing: Relationship[]; incoming: IncomingRelationship[] },
): string {
  switch (result.mode) {
    case "outgoing":
      return renderOutgoingRelationships(result.id, result.relationships);
    case "incoming":
      return renderIncomingRelationships(result.id, result.relationships);
    case "related":
      return [renderOutgoingRelationships(result.id, result.outgoing), "", renderIncomingRelationships(result.id, result.incoming)].join(
        "\n",
      );
  }
}
