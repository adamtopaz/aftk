import {
  ToolkitProtocolError,
  type ToolkitRuntimeErrorDetails,
} from "../runtime/errors.ts";
import {
  createToolkitRuntimeContext,
  type ToolkitRuntimeContext,
  type ToolkitRuntimeOptions,
} from "../runtime/options.ts";
import { runToolkitCliCommand } from "../runtime/cli.ts";
import type { ToolkitDiagnostics, ToolkitWarning } from "../output/result.ts";

export type NodeKind =
  | "note"
  | "definition"
  | "theorem"
  | "proofSketch"
  | "example"
  | "explanation"
  | "concept"
  | "documentation";

export type NodeStatus = "draft" | "active" | "deprecated" | "archived";

export type RelationshipKind =
  | "relatedTo"
  | "dependsOn"
  | "elaborates"
  | "refines"
  | "exampleOf"
  | "hasExample"
  | "seeAlso";

export interface Relationship {
  kind: RelationshipKind;
  target: string;
  label?: string;
  note?: string;
}

export interface LeanDeclRef {
  module?: string;
  declaration: string;
  kind?: string;
}

export interface NodeMetadata {
  schemaVersion: number;
  id: string;
  title: string;
  kind: NodeKind;
  status: NodeStatus;
  summary?: string;
  tags: string[];
  authors: string[];
  createdAt?: string;
  updatedAt?: string;
  relationships: Relationship[];
  leanRefs: LeanDeclRef[];
}

export interface Node {
  metadata: NodeMetadata;
  body: string;
}

export interface NodePaths {
  markdownPath: string;
  metadataPath: string;
}

export interface StoredNode {
  node: Node;
  paths: NodePaths;
}

export interface StorageManifest {
  schemaVersion: number;
  kind: string;
  nodesDir: string;
  internalDir: string;
}

export interface StatusInfo {
  root: string;
  manifest: StorageManifest;
  initialized: boolean;
  nodeCount: number;
  internalDirExists: boolean;
  indexDirExists: boolean;
  cacheDirExists: boolean;
  tmpDirExists: boolean;
}

export type SearchScope = "bodyText" | "title" | "summary" | "tags" | "metadata" | "allText";

export interface SearchHit {
  id: string;
  score?: number;
  title?: string;
  summary?: string;
  matchedScopes: SearchScope[];
  snippet?: string;
}

export interface SearchResult {
  hits: SearchHit[];
}

export interface IncomingRelationship {
  source: string;
  sourceTitle?: string;
  relationship: Relationship;
}

export interface RelatedRelationships {
  id: string;
  outgoing: Relationship[];
  incoming: IncomingRelationship[];
}

export type ValidationSeverity = "error" | "warning" | "info";

export type ValidationScope =
  | { kind: "storage" }
  | { kind: "node"; id: string }
  | { kind: "metadata"; id: string }
  | { kind: "relationships"; id: string }
  | { kind: "wholeKnowledgeBase" };

export interface ValidationIssue {
  code: string;
  severity: ValidationSeverity;
  scope: ValidationScope;
  message: string;
  path?: string;
  relatedNodeId?: string;
}

export interface ValidationReport {
  ok: boolean;
  issues: ValidationIssue[];
}

export type KnowledgeBaseShowView = "combined" | "body" | "metadata" | "paths";
export type KnowledgeBaseRelationshipsMode = "outgoing" | "incoming" | "related";
export type KnowledgeBaseValidationScope = "storage" | "node" | "metadata" | "all";

export interface KnowledgeBaseStatusResult extends StatusInfo {}

export interface KnowledgeBaseListResult {
  items: NodeMetadata[];
  count: number;
  filters: {
    prefix?: string;
    kind?: NodeKind;
    status?: NodeStatus;
    tag?: string;
  };
}

export interface KnowledgeBaseShowResult {
  id: string;
  view: KnowledgeBaseShowView;
  value: StoredNode | string | NodeMetadata | NodePaths;
}

export interface KnowledgeBaseSearchTextResult {
  query: string;
  limit?: number;
  hits: SearchHit[];
  count: number;
}

export interface KnowledgeBaseSearchTagResult {
  tag: string;
  limit?: number;
  hits: SearchHit[];
  count: number;
}

export type KnowledgeBaseRelationshipsResult =
  | { id: string; mode: "outgoing"; relationships: Relationship[] }
  | { id: string; mode: "incoming"; relationships: IncomingRelationship[] }
  | { id: string; mode: "related"; outgoing: Relationship[]; incoming: IncomingRelationship[] };

export interface KnowledgeBaseValidationResult {
  scope: KnowledgeBaseValidationScope;
  targetId?: string;
  report: ValidationReport;
}

export interface KnowledgeBaseCliSuccess<T> {
  ok: true;
  command: string;
  root: string;
  warnings: ToolkitWarning[];
  exitCode: number | null;
  diagnostics: ToolkitDiagnostics;
  result: T;
}

export interface KnowledgeBaseCliFailure {
  ok: false;
  command: string;
  root?: string;
  warnings: ToolkitWarning[];
  exitCode: number | null;
  diagnostics: ToolkitDiagnostics;
  error: {
    code?: string;
    message: string;
  };
}

export type KnowledgeBaseCliResponse<T> = KnowledgeBaseCliSuccess<T> | KnowledgeBaseCliFailure;

interface KnowledgeBaseEnvelopeSuccess {
  command: string;
  root: string;
  ok: true;
  result: unknown;
  warnings: ToolkitWarning[];
}

interface KnowledgeBaseEnvelopeFailure {
  command: string;
  root: string;
  ok: false;
  error: {
    code?: string;
    message: string;
  };
  warnings: ToolkitWarning[];
}

type KnowledgeBaseEnvelope = KnowledgeBaseEnvelopeSuccess | KnowledgeBaseEnvelopeFailure;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function diagnosticsFor(command: { stdout: string; stderr: string; exitCode: number | null; signal: NodeJS.Signals | null; durationMs: number; forcedKill: boolean }): ToolkitDiagnostics {
  return {
    stdout: command.stdout,
    stderr: command.stderr,
    exitCode: command.exitCode,
    signal: command.signal,
    durationMs: command.durationMs,
    forcedKill: command.forcedKill,
  };
}

function protocolError(message: string, details: ToolkitRuntimeErrorDetails): ToolkitProtocolError {
  return new ToolkitProtocolError(message, details);
}

function expectRecord(value: unknown, label: string, diagnostics?: ToolkitDiagnostics): Record<string, unknown> {
  if (!isRecord(value)) {
    throw protocolError(`Knowledge-base JSON field '${label}' was not an object.`, {
      stdout: diagnostics?.stdout,
      stderr: diagnostics?.stderr,
      exitCode: diagnostics?.exitCode,
      signal: diagnostics?.signal,
      durationMs: diagnostics?.durationMs,
      forcedKill: diagnostics?.forcedKill,
      data: value,
    });
  }
  return value;
}

function expectString(value: unknown, label: string, diagnostics?: ToolkitDiagnostics): string {
  if (typeof value !== "string") {
    throw protocolError(`Knowledge-base JSON field '${label}' was not a string.`, {
      stdout: diagnostics?.stdout,
      stderr: diagnostics?.stderr,
      exitCode: diagnostics?.exitCode,
      signal: diagnostics?.signal,
      durationMs: diagnostics?.durationMs,
      forcedKill: diagnostics?.forcedKill,
      data: value,
    });
  }
  return value;
}

function expectBoolean(value: unknown, label: string, diagnostics?: ToolkitDiagnostics): boolean {
  if (typeof value !== "boolean") {
    throw protocolError(`Knowledge-base JSON field '${label}' was not a boolean.`, {
      stdout: diagnostics?.stdout,
      stderr: diagnostics?.stderr,
      exitCode: diagnostics?.exitCode,
      signal: diagnostics?.signal,
      durationMs: diagnostics?.durationMs,
      forcedKill: diagnostics?.forcedKill,
      data: value,
    });
  }
  return value;
}

function expectNumber(value: unknown, label: string, diagnostics?: ToolkitDiagnostics): number {
  if (typeof value !== "number" || Number.isNaN(value)) {
    throw protocolError(`Knowledge-base JSON field '${label}' was not a number.`, {
      stdout: diagnostics?.stdout,
      stderr: diagnostics?.stderr,
      exitCode: diagnostics?.exitCode,
      signal: diagnostics?.signal,
      durationMs: diagnostics?.durationMs,
      forcedKill: diagnostics?.forcedKill,
      data: value,
    });
  }
  return value;
}

function expectArray(value: unknown, label: string, diagnostics?: ToolkitDiagnostics): unknown[] {
  if (!Array.isArray(value)) {
    throw protocolError(`Knowledge-base JSON field '${label}' was not an array.`, {
      stdout: diagnostics?.stdout,
      stderr: diagnostics?.stderr,
      exitCode: diagnostics?.exitCode,
      signal: diagnostics?.signal,
      durationMs: diagnostics?.durationMs,
      forcedKill: diagnostics?.forcedKill,
      data: value,
    });
  }
  return value;
}

function optionalString(value: unknown, label: string, diagnostics?: ToolkitDiagnostics): string | undefined {
  if (value === undefined) {
    return undefined;
  }
  return expectString(value, label, diagnostics);
}

function stringArray(value: unknown, label: string, diagnostics?: ToolkitDiagnostics): string[] {
  return expectArray(value, label, diagnostics).map((item, index) => expectString(item, `${label}[${index}]`, diagnostics));
}

function parseWarnings(value: unknown, diagnostics?: ToolkitDiagnostics): ToolkitWarning[] {
  if (value === undefined) {
    return [];
  }
  return expectArray(value, "warnings", diagnostics).map((item, index) => {
    const record = expectRecord(item, `warnings[${index}]`, diagnostics);
    return {
      code: optionalString(record.code, `warnings[${index}].code`, diagnostics),
      message: expectString(record.message, `warnings[${index}].message`, diagnostics),
    };
  });
}

function parseRelationship(value: unknown, diagnostics?: ToolkitDiagnostics): Relationship {
  const record = expectRecord(value, "relationship", diagnostics);
  return {
    kind: expectString(record.kind, "relationship.kind", diagnostics) as RelationshipKind,
    target: expectString(record.target, "relationship.target", diagnostics),
    label: optionalString(record.label, "relationship.label", diagnostics),
    note: optionalString(record.note, "relationship.note", diagnostics),
  };
}

function parseLeanDeclRef(value: unknown, diagnostics?: ToolkitDiagnostics): LeanDeclRef {
  const record = expectRecord(value, "leanRef", diagnostics);
  return {
    module: optionalString(record.module, "leanRef.module", diagnostics),
    declaration: expectString(record.declaration, "leanRef.declaration", diagnostics),
    kind: optionalString(record.kind, "leanRef.kind", diagnostics),
  };
}

function parseNodeMetadata(value: unknown, diagnostics?: ToolkitDiagnostics): NodeMetadata {
  const record = expectRecord(value, "metadata", diagnostics);
  return {
    schemaVersion: typeof record.schemaVersion === "number" ? record.schemaVersion : 1,
    id: expectString(record.id, "metadata.id", diagnostics),
    title: expectString(record.title, "metadata.title", diagnostics),
    kind: (optionalString(record.kind, "metadata.kind", diagnostics) ?? "note") as NodeKind,
    status: (optionalString(record.status, "metadata.status", diagnostics) ?? "draft") as NodeStatus,
    summary: optionalString(record.summary, "metadata.summary", diagnostics),
    tags: record.tags === undefined ? [] : stringArray(record.tags, "metadata.tags", diagnostics),
    authors: record.authors === undefined ? [] : stringArray(record.authors, "metadata.authors", diagnostics),
    createdAt: optionalString(record.createdAt, "metadata.createdAt", diagnostics),
    updatedAt: optionalString(record.updatedAt, "metadata.updatedAt", diagnostics),
    relationships:
      record.relationships === undefined
        ? []
        : expectArray(record.relationships, "metadata.relationships", diagnostics).map((item) => parseRelationship(item, diagnostics)),
    leanRefs:
      record.leanRefs === undefined
        ? []
        : expectArray(record.leanRefs, "metadata.leanRefs", diagnostics).map((item) => parseLeanDeclRef(item, diagnostics)),
  };
}

function parseNodePaths(value: unknown, diagnostics?: ToolkitDiagnostics): NodePaths {
  const record = expectRecord(value, "paths", diagnostics);
  return {
    markdownPath: expectString(record.markdownPath, "paths.markdownPath", diagnostics),
    metadataPath: expectString(record.metadataPath, "paths.metadataPath", diagnostics),
  };
}

function parseStoredNode(value: unknown, diagnostics?: ToolkitDiagnostics): StoredNode {
  const record = expectRecord(value, "storedNode", diagnostics);
  const node = expectRecord(record.node, "storedNode.node", diagnostics);
  return {
    node: {
      metadata: parseNodeMetadata(node.metadata, diagnostics),
      body: expectString(node.body, "storedNode.node.body", diagnostics),
    },
    paths: parseNodePaths(record.paths, diagnostics),
  };
}

function parseManifest(value: unknown, diagnostics?: ToolkitDiagnostics): StorageManifest {
  const record = expectRecord(value, "manifest", diagnostics);
  return {
    schemaVersion: expectNumber(record.schemaVersion, "manifest.schemaVersion", diagnostics),
    kind: expectString(record.kind, "manifest.kind", diagnostics),
    nodesDir: expectString(record.nodesDir, "manifest.nodesDir", diagnostics),
    internalDir: expectString(record.internalDir, "manifest.internalDir", diagnostics),
  };
}

function parseStatusInfo(value: unknown, diagnostics?: ToolkitDiagnostics): StatusInfo {
  const record = expectRecord(value, "status", diagnostics);
  return {
    root: expectString(record.root, "status.root", diagnostics),
    manifest: parseManifest(record.manifest, diagnostics),
    initialized: expectBoolean(record.initialized, "status.initialized", diagnostics),
    nodeCount: expectNumber(record.nodeCount, "status.nodeCount", diagnostics),
    internalDirExists: expectBoolean(record.internalDirExists, "status.internalDirExists", diagnostics),
    indexDirExists: expectBoolean(record.indexDirExists, "status.indexDirExists", diagnostics),
    cacheDirExists: expectBoolean(record.cacheDirExists, "status.cacheDirExists", diagnostics),
    tmpDirExists: expectBoolean(record.tmpDirExists, "status.tmpDirExists", diagnostics),
  };
}

function parseSearchHit(value: unknown, diagnostics?: ToolkitDiagnostics): SearchHit {
  const record = expectRecord(value, "searchHit", diagnostics);
  return {
    id: expectString(record.id, "searchHit.id", diagnostics),
    score: record.score === undefined ? undefined : expectNumber(record.score, "searchHit.score", diagnostics),
    title: optionalString(record.title, "searchHit.title", diagnostics),
    summary: optionalString(record.summary, "searchHit.summary", diagnostics),
    matchedScopes:
      record.matchedScopes === undefined ? [] : (stringArray(record.matchedScopes, "searchHit.matchedScopes", diagnostics) as SearchScope[]),
    snippet: optionalString(record.snippet, "searchHit.snippet", diagnostics),
  };
}

function parseSearchResult(value: unknown, diagnostics?: ToolkitDiagnostics): SearchResult {
  const record = expectRecord(value, "searchResult", diagnostics);
  return {
    hits: expectArray(record.hits, "searchResult.hits", diagnostics).map((item) => parseSearchHit(item, diagnostics)),
  };
}

function parseIncomingRelationship(value: unknown, diagnostics?: ToolkitDiagnostics): IncomingRelationship {
  const record = expectRecord(value, "incomingRelationship", diagnostics);
  return {
    source: expectString(record.source, "incomingRelationship.source", diagnostics),
    sourceTitle: optionalString(record.sourceTitle, "incomingRelationship.sourceTitle", diagnostics),
    relationship: parseRelationship(record.relationship, diagnostics),
  };
}

function parseRelatedRelationships(value: unknown, diagnostics?: ToolkitDiagnostics): RelatedRelationships {
  const record = expectRecord(value, "relatedRelationships", diagnostics);
  return {
    id: expectString(record.id, "relatedRelationships.id", diagnostics),
    outgoing: expectArray(record.outgoing, "relatedRelationships.outgoing", diagnostics).map((item) => parseRelationship(item, diagnostics)),
    incoming: expectArray(record.incoming, "relatedRelationships.incoming", diagnostics).map((item) => parseIncomingRelationship(item, diagnostics)),
  };
}

function parseValidationScope(value: unknown, diagnostics?: ToolkitDiagnostics): ValidationScope {
  const record = expectRecord(value, "validationScope", diagnostics);
  const kind = expectString(record.kind, "validationScope.kind", diagnostics);
  switch (kind) {
    case "storage":
      return { kind: "storage" };
    case "node":
      return { kind: "node", id: expectString(record.id, "validationScope.id", diagnostics) };
    case "metadata":
      return { kind: "metadata", id: expectString(record.id, "validationScope.id", diagnostics) };
    case "relationships":
      return { kind: "relationships", id: expectString(record.id, "validationScope.id", diagnostics) };
    case "wholeKnowledgeBase":
      return { kind: "wholeKnowledgeBase" };
    default:
      throw protocolError(`Knowledge-base validation scope kind '${kind}' was not recognized.`, {
        data: value,
        stdout: diagnostics?.stdout,
        stderr: diagnostics?.stderr,
      });
  }
}

function parseValidationIssue(value: unknown, diagnostics?: ToolkitDiagnostics): ValidationIssue {
  const record = expectRecord(value, "validationIssue", diagnostics);
  return {
    code: expectString(record.code, "validationIssue.code", diagnostics),
    severity: expectString(record.severity, "validationIssue.severity", diagnostics) as ValidationSeverity,
    scope: parseValidationScope(record.scope, diagnostics),
    message: expectString(record.message, "validationIssue.message", diagnostics),
    path: optionalString(record.path, "validationIssue.path", diagnostics),
    relatedNodeId: optionalString(record.relatedNodeId, "validationIssue.relatedNodeId", diagnostics),
  };
}

function parseValidationReport(value: unknown, diagnostics?: ToolkitDiagnostics): ValidationReport {
  const record = expectRecord(value, "validationReport", diagnostics);
  return {
    ok: expectBoolean(record.ok, "validationReport.ok", diagnostics),
    issues: expectArray(record.issues, "validationReport.issues", diagnostics).map((item) => parseValidationIssue(item, diagnostics)),
  };
}

function parseEnvelope(stdout: string, diagnostics: ToolkitDiagnostics): KnowledgeBaseEnvelope {
  let parsed: unknown;
  try {
    parsed = JSON.parse(stdout);
  } catch {
    throw protocolError(`Knowledge-base CLI did not emit valid JSON.`, {
      stdout,
      stderr: diagnostics.stderr,
      exitCode: diagnostics.exitCode,
      signal: diagnostics.signal,
      durationMs: diagnostics.durationMs,
      forcedKill: diagnostics.forcedKill,
    });
  }

  const record = expectRecord(parsed, "envelope", diagnostics);
  const command = expectString(record.command, "envelope.command", diagnostics);
  const root = expectString(record.root, "envelope.root", diagnostics);
  const ok = expectBoolean(record.ok, "envelope.ok", diagnostics);
  const warnings = parseWarnings(record.warnings, diagnostics);

  if (ok) {
    return {
      command,
      root,
      ok: true,
      result: record.result,
      warnings,
    };
  }

  const errorRecord = expectRecord(record.error, "envelope.error", diagnostics);
  return {
    command,
    root,
    ok: false,
    error: {
      code: optionalString(errorRecord.code, "envelope.error.code", diagnostics),
      message: expectString(errorRecord.message, "envelope.error.message", diagnostics),
    },
    warnings,
  };
}

export interface KnowledgeBaseCommandOptions {
  root?: string;
  signal?: AbortSignal;
  timeoutMs?: number;
}

export interface KnowledgeBaseListOptions extends KnowledgeBaseCommandOptions {
  prefix?: string;
  kind?: NodeKind;
  status?: NodeStatus;
  tag?: string;
}

export interface KnowledgeBaseShowOptions extends KnowledgeBaseCommandOptions {
  view?: KnowledgeBaseShowView;
}

export interface KnowledgeBaseSearchOptions extends KnowledgeBaseCommandOptions {
  limit?: number;
}

export interface CreateKnowledgeBaseClientOptions extends ToolkitRuntimeOptions {
  runtime?: ToolkitRuntimeContext;
}

export class KnowledgeBaseClient {
  readonly runtime: ToolkitRuntimeContext;

  constructor(options: CreateKnowledgeBaseClientOptions = {}) {
    this.runtime = options.runtime ?? createToolkitRuntimeContext(options);
  }

  private async execute<T>(
    args: string[],
    parser: (result: unknown, diagnostics: ToolkitDiagnostics) => T,
    options: KnowledgeBaseCommandOptions = {},
  ): Promise<KnowledgeBaseCliResponse<T>> {
    const rootArgs = options.root !== undefined ? ["--root", options.root] : [];
    const completed = await runToolkitCliCommand(
      this.runtime,
      "knowledgebase",
      [...rootArgs, "--format", "json", ...args],
      {
        signal: options.signal,
        timeoutMs: options.timeoutMs,
      },
    );

    const diagnostics = diagnosticsFor(completed);
    const envelope = parseEnvelope(completed.stdout, diagnostics);
    if (!envelope.ok) {
      return {
        ok: false,
        command: envelope.command,
        root: envelope.root,
        warnings: envelope.warnings,
        exitCode: completed.exitCode,
        diagnostics: {
          ...diagnostics,
          raw: envelope,
        },
        error: envelope.error,
      };
    }

    return {
      ok: true,
      command: envelope.command,
      root: envelope.root,
      warnings: envelope.warnings,
      exitCode: completed.exitCode,
      diagnostics: {
        ...diagnostics,
        raw: envelope,
      },
      result: parser(envelope.result, diagnostics),
    };
  }

  async status(options: KnowledgeBaseCommandOptions = {}): Promise<KnowledgeBaseCliResponse<KnowledgeBaseStatusResult>> {
    return await this.execute(["status"], (result, diagnostics) => parseStatusInfo(result, diagnostics), options);
  }

  async list(options: KnowledgeBaseListOptions = {}): Promise<KnowledgeBaseCliResponse<KnowledgeBaseListResult>> {
    const args = ["list"];
    if (options.prefix !== undefined) args.push("--prefix", options.prefix);
    if (options.kind !== undefined) args.push("--kind", options.kind);
    if (options.status !== undefined) args.push("--status", options.status);
    if (options.tag !== undefined) args.push("--tag", options.tag);
    return await this.execute(
      args,
      (result, diagnostics) => {
        const record = expectRecord(result, "listResult", diagnostics);
        const items = expectArray(record.nodes, "listResult.nodes", diagnostics).map((item) => parseNodeMetadata(item, diagnostics));
        return {
          items,
          count: items.length,
          filters: {
            prefix: options.prefix,
            kind: options.kind,
            status: options.status,
            tag: options.tag,
          },
        };
      },
      options,
    );
  }

  async show(id: string, options: KnowledgeBaseShowOptions = {}): Promise<KnowledgeBaseCliResponse<KnowledgeBaseShowResult>> {
    const view = options.view ?? "combined";
    const args = ["show", id];
    if (view === "body") args.push("--body");
    if (view === "metadata") args.push("--metadata");
    if (view === "paths") args.push("--paths");
    return await this.execute(
      args,
      (result, diagnostics) => {
        if (view === "combined") {
          return {
            id,
            view,
            value: parseStoredNode(result, diagnostics),
          };
        }
        if (view === "body") {
          const record = expectRecord(result, "show.bodyResult", diagnostics);
          return {
            id,
            view,
            value: expectString(record.body, "show.bodyResult.body", diagnostics),
          };
        }
        if (view === "metadata") {
          const record = expectRecord(result, "show.metadataResult", diagnostics);
          return {
            id,
            view,
            value: parseNodeMetadata(record.metadata, diagnostics),
          };
        }
        const record = expectRecord(result, "show.pathsResult", diagnostics);
        return {
          id,
          view,
          value: parseNodePaths(record.paths, diagnostics),
        };
      },
      options,
    );
  }

  async searchText(
    query: string,
    options: KnowledgeBaseSearchOptions = {},
  ): Promise<KnowledgeBaseCliResponse<KnowledgeBaseSearchTextResult>> {
    const args = ["search", "text", query];
    if (options.limit !== undefined) args.push("--limit", String(options.limit));
    return await this.execute(
      args,
      (result, diagnostics) => {
        const parsed = parseSearchResult(result, diagnostics);
        return {
          query,
          limit: options.limit,
          hits: parsed.hits,
          count: parsed.hits.length,
        };
      },
      options,
    );
  }

  async searchTag(
    tag: string,
    options: KnowledgeBaseSearchOptions = {},
  ): Promise<KnowledgeBaseCliResponse<KnowledgeBaseSearchTagResult>> {
    const args = ["search", "tag", tag];
    if (options.limit !== undefined) args.push("--limit", String(options.limit));
    return await this.execute(
      args,
      (result, diagnostics) => {
        const parsed = parseSearchResult(result, diagnostics);
        return {
          tag,
          limit: options.limit,
          hits: parsed.hits,
          count: parsed.hits.length,
        };
      },
      options,
    );
  }

  async relationships(
    id: string,
    mode: KnowledgeBaseRelationshipsMode,
    options: KnowledgeBaseCommandOptions = {},
  ): Promise<KnowledgeBaseCliResponse<KnowledgeBaseRelationshipsResult>> {
    return await this.execute(
      ["relationships", mode, id],
      (result, diagnostics) => {
        if (mode === "outgoing") {
          const record = expectRecord(result, "relationships.outgoing", diagnostics);
          return {
            id,
            mode,
            relationships: expectArray(record.relationships, "relationships.outgoing.relationships", diagnostics).map((item) =>
              parseRelationship(item, diagnostics),
            ),
          };
        }
        if (mode === "incoming") {
          const record = expectRecord(result, "relationships.incoming", diagnostics);
          return {
            id,
            mode,
            relationships: expectArray(record.relationships, "relationships.incoming.relationships", diagnostics).map((item) =>
              parseIncomingRelationship(item, diagnostics),
            ),
          };
        }
        const parsed = parseRelatedRelationships(result, diagnostics);
        return {
          id,
          mode,
          outgoing: parsed.outgoing,
          incoming: parsed.incoming,
        };
      },
      options,
    );
  }

  async validateStorage(
    options: KnowledgeBaseCommandOptions = {},
  ): Promise<KnowledgeBaseCliResponse<KnowledgeBaseValidationResult>> {
    return await this.execute(
      ["validate", "storage"],
      (result, diagnostics) => ({
        scope: "storage",
        report: parseValidationReport(result, diagnostics),
      }),
      options,
    );
  }

  async validateNode(
    id: string,
    options: KnowledgeBaseCommandOptions = {},
  ): Promise<KnowledgeBaseCliResponse<KnowledgeBaseValidationResult>> {
    return await this.execute(
      ["validate", "node", id],
      (result, diagnostics) => ({
        scope: "node",
        targetId: id,
        report: parseValidationReport(result, diagnostics),
      }),
      options,
    );
  }

  async validateMetadata(
    id: string,
    options: KnowledgeBaseCommandOptions = {},
  ): Promise<KnowledgeBaseCliResponse<KnowledgeBaseValidationResult>> {
    return await this.execute(
      ["metadata", "validate", id],
      (result, diagnostics) => ({
        scope: "metadata",
        targetId: id,
        report: parseValidationReport(result, diagnostics),
      }),
      options,
    );
  }

  async validateAll(
    options: KnowledgeBaseCommandOptions = {},
  ): Promise<KnowledgeBaseCliResponse<KnowledgeBaseValidationResult>> {
    return await this.execute(
      ["validate", "all"],
      (result, diagnostics) => ({
        scope: "all",
        report: parseValidationReport(result, diagnostics),
      }),
      options,
    );
  }
}
