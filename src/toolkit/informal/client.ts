import { ToolkitProtocolError, type ToolkitRuntimeErrorDetails } from "../runtime/errors.ts";
import {
  createToolkitRuntimeContext,
  type ToolkitRuntimeContext,
  type ToolkitRuntimeOptions,
} from "../runtime/options.ts";
import { runToolkitCliCommand } from "../runtime/cli.ts";
import type { ToolkitDiagnostics } from "../output/result.ts";

export interface InformalDeclEntry {
  declName: string;
  refCount: number;
  refs: string[];
}

export interface InformalReferenceEntry {
  ref: string;
  declCount: number;
  declNames: string[];
}

export interface InformalDeclDependencyRow {
  declName: string;
  dependencies: string[];
}

export interface InformalReferenceDependencyRow {
  ref: string;
  dependencies: string[];
}

export interface InformalPresentationSummary {
  ref: string;
  title: string;
  kind?: string;
  status?: string;
  summary?: string;
}

export type InformalBodyPresentation =
  | { kind: "none" }
  | { kind: "preview"; truncated: boolean; text: string }
  | { kind: "full"; text: string };

export interface InformalPresentationPayload {
  summary: InformalPresentationSummary;
  tags: string[];
  authors: string[];
  relationshipLines: string[];
  leanRefLines: string[];
  body: InformalBodyPresentation;
}

export interface InformalStatusResult {
  modules: string[];
  trackedDeclarations: number;
  trackedReferences: number;
  declarationsWithMultipleReferences: number;
}

export interface InformalDeclsResult {
  modules: string[];
  filters: {
    prefix?: string;
    ref?: string;
  };
  entries: InformalDeclEntry[];
  count: number;
}

export interface InformalDeclResult {
  modules: string[];
  target: string;
  entry: InformalDeclEntry;
}

export interface InformalRefsResult {
  modules: string[];
  filters: {
    prefix?: string;
  };
  entries: InformalReferenceEntry[];
  count: number;
}

export interface InformalRefResult {
  modules: string[];
  target: string;
  entry: InformalReferenceEntry;
}

export type InformalDepsResult =
  | {
      modules: string[];
      mode: "decl";
      onlyLeaves: boolean;
      rows: InformalDeclDependencyRow[];
      leaves: string[];
    }
  | {
      modules: string[];
      mode: "ref";
      onlyLeaves: boolean;
      rows: InformalReferenceDependencyRow[];
      leaves: string[];
    };

export type InformalPresentResult =
  | {
      target: string;
      mode: "compact";
      summary: InformalPresentationSummary;
    }
  | {
      target: string;
      mode: "rich";
      bodyMode: "none" | "preview" | "full";
      payload: InformalPresentationPayload;
    };

export interface InformalCliSuccess<T> {
  ok: true;
  command: string;
  modules?: string[];
  target?: string;
  mode?: string;
  bodyMode?: string;
  diagnostics: ToolkitDiagnostics;
  result: T;
}

export interface InformalCliFailure {
  ok: false;
  command?: string;
  diagnostics: ToolkitDiagnostics;
  error: {
    code?: string;
    message: string;
    exitCode?: number;
  };
}

export type InformalCliResponse<T> = InformalCliSuccess<T> | InformalCliFailure;

export interface InformalCommandOptions {
  signal?: AbortSignal;
  timeoutMs?: number;
}

export interface InformalEnvironmentOptions extends InformalCommandOptions {
  modules: string[];
}

export interface InformalDeclsOptions extends InformalEnvironmentOptions {
  prefix?: string;
  ref?: string;
}

export interface InformalRefsOptions extends InformalEnvironmentOptions {
  prefix?: string;
}

export interface InformalDepsOptions extends InformalEnvironmentOptions {
  mode?: "decl" | "ref";
  onlyLeaves?: boolean;
}

export interface InformalPresentOptions extends InformalCommandOptions {
  root?: string;
  mode?: "compact" | "rich";
  body?: "none" | "preview" | "full";
}

export interface CreateInformalClientOptions extends ToolkitRuntimeOptions {
  runtime?: ToolkitRuntimeContext;
}

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
    throw protocolError(`Informal CLI JSON field '${label}' was not an object.`, {
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
    throw protocolError(`Informal CLI JSON field '${label}' was not a string.`, {
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
    throw protocolError(`Informal CLI JSON field '${label}' was not a boolean.`, {
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
    throw protocolError(`Informal CLI JSON field '${label}' was not a number.`, {
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
    throw protocolError(`Informal CLI JSON field '${label}' was not an array.`, {
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

function parseDeclEntry(value: unknown, diagnostics?: ToolkitDiagnostics): InformalDeclEntry {
  const record = expectRecord(value, "declEntry", diagnostics);
  return {
    declName: expectString(record.declName, "declEntry.declName", diagnostics),
    refCount: expectNumber(record.refCount, "declEntry.refCount", diagnostics),
    refs: stringArray(record.refs, "declEntry.refs", diagnostics),
  };
}

function parseRefEntry(value: unknown, diagnostics?: ToolkitDiagnostics): InformalReferenceEntry {
  const record = expectRecord(value, "refEntry", diagnostics);
  return {
    ref: expectString(record.ref, "refEntry.ref", diagnostics),
    declCount: expectNumber(record.declCount, "refEntry.declCount", diagnostics),
    declNames: stringArray(record.declNames, "refEntry.declNames", diagnostics),
  };
}

function parsePresentationSummary(value: unknown, diagnostics?: ToolkitDiagnostics): InformalPresentationSummary {
  const record = expectRecord(value, "presentationSummary", diagnostics);
  return {
    ref: expectString(record.ref, "presentationSummary.ref", diagnostics),
    title: expectString(record.title, "presentationSummary.title", diagnostics),
    kind: optionalString(record.kind, "presentationSummary.kind", diagnostics),
    status: optionalString(record.status, "presentationSummary.status", diagnostics),
    summary: optionalString(record.summary, "presentationSummary.summary", diagnostics),
  };
}

function parseBodyPresentation(value: unknown, diagnostics?: ToolkitDiagnostics): InformalBodyPresentation {
  const record = expectRecord(value, "body", diagnostics);
  const kind = expectString(record.kind, "body.kind", diagnostics);
  switch (kind) {
    case "none":
      return { kind: "none" };
    case "preview":
      return {
        kind: "preview",
        truncated: expectBoolean(record.truncated, "body.truncated", diagnostics),
        text: expectString(record.text, "body.text", diagnostics),
      };
    case "full":
      return {
        kind: "full",
        text: expectString(record.text, "body.text", diagnostics),
      };
    default:
      throw protocolError(`Informal body presentation kind '${kind}' was not recognized.`, {
        stdout: diagnostics?.stdout,
        stderr: diagnostics?.stderr,
        data: value,
      });
  }
}

function parsePresentationPayload(value: unknown, diagnostics?: ToolkitDiagnostics): InformalPresentationPayload {
  const record = expectRecord(value, "presentationPayload", diagnostics);
  return {
    summary: parsePresentationSummary(record.summary, diagnostics),
    tags: record.tags === undefined ? [] : stringArray(record.tags, "presentationPayload.tags", diagnostics),
    authors: record.authors === undefined ? [] : stringArray(record.authors, "presentationPayload.authors", diagnostics),
    relationshipLines:
      record.relationshipLines === undefined
        ? []
        : stringArray(record.relationshipLines, "presentationPayload.relationshipLines", diagnostics),
    leanRefLines:
      record.leanRefLines === undefined ? [] : stringArray(record.leanRefLines, "presentationPayload.leanRefLines", diagnostics),
    body: parseBodyPresentation(record.body, diagnostics),
  };
}

function parseModules(record: Record<string, unknown>, diagnostics?: ToolkitDiagnostics): string[] | undefined {
  if (record.modules === undefined) {
    return undefined;
  }
  return stringArray(record.modules, "modules", diagnostics);
}

function parseSuccess(stdout: string, diagnostics: ToolkitDiagnostics): Record<string, unknown> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(stdout);
  } catch {
    throw protocolError(`Informal CLI did not emit valid JSON.`, {
      stdout,
      stderr: diagnostics.stderr,
      exitCode: diagnostics.exitCode,
      signal: diagnostics.signal,
      durationMs: diagnostics.durationMs,
      forcedKill: diagnostics.forcedKill,
    });
  }
  return expectRecord(parsed, "response", diagnostics);
}

function modulesArgs(modules: string[]): string[] {
  return modules.flatMap((moduleName) => ["--module", moduleName]);
}

function rootArgs(root: string | undefined): string[] {
  return root === undefined ? [] : ["--root", root];
}

export class InformalClient {
  readonly runtime: ToolkitRuntimeContext;

  constructor(options: CreateInformalClientOptions = {}) {
    this.runtime = options.runtime ?? createToolkitRuntimeContext(options);
  }

  private async execute<T>(
    args: string[],
    parser: (record: Record<string, unknown>, diagnostics: ToolkitDiagnostics) => InformalCliResponse<T>,
    options: InformalCommandOptions = {},
  ): Promise<InformalCliResponse<T>> {
    const completed = await runToolkitCliCommand(this.runtime, "informal", ["--format", "json", ...args], {
      signal: options.signal,
      timeoutMs: options.timeoutMs,
    });
    const diagnostics = diagnosticsFor(completed);
    const record = parseSuccess(completed.stdout, diagnostics);
    if (record.ok === false) {
      const errorRecord = expectRecord(record.error, "response.error", diagnostics);
      return {
        ok: false,
        command: record.command === undefined ? undefined : expectString(record.command, "response.command", diagnostics),
        diagnostics: {
          ...diagnostics,
          raw: record,
        },
        error: {
          code: optionalString(errorRecord.code, "response.error.code", diagnostics),
          message: expectString(errorRecord.message, "response.error.message", diagnostics),
          exitCode:
            errorRecord.exitCode === undefined ? undefined : expectNumber(errorRecord.exitCode, "response.error.exitCode", diagnostics),
        },
      };
    }
    return parser(record, {
      ...diagnostics,
      raw: record,
    });
  }

  async status(options: InformalEnvironmentOptions): Promise<InformalCliResponse<InformalStatusResult>> {
    return await this.execute(
      [...modulesArgs(options.modules), "status"],
      (record, diagnostics) => {
        const data = expectRecord(record.data, "status.data", diagnostics);
        const modules = parseModules(record, diagnostics) ?? [];
        return {
          ok: true,
          command: expectString(record.command, "status.command", diagnostics),
          modules,
          diagnostics,
          result: {
            modules,
            trackedDeclarations: expectNumber(data.trackedDeclarations, "status.data.trackedDeclarations", diagnostics),
            trackedReferences: expectNumber(data.trackedReferences, "status.data.trackedReferences", diagnostics),
            declarationsWithMultipleReferences: expectNumber(
              data.declarationsWithMultipleReferences,
              "status.data.declarationsWithMultipleReferences",
              diagnostics,
            ),
          },
        };
      },
      options,
    );
  }

  async decls(options: InformalDeclsOptions): Promise<InformalCliResponse<InformalDeclsResult>> {
    const args = [...modulesArgs(options.modules), "decls"];
    if (options.prefix !== undefined) args.push("--prefix", options.prefix);
    if (options.ref !== undefined) args.push("--ref", options.ref);
    return await this.execute(
      args,
      (record, diagnostics) => {
        const data = expectRecord(record.data, "decls.data", diagnostics);
        const entries = expectArray(data.entries, "decls.data.entries", diagnostics).map((item) => parseDeclEntry(item, diagnostics));
        const modules = parseModules(record, diagnostics) ?? [];
        return {
          ok: true,
          command: expectString(record.command, "decls.command", diagnostics),
          modules,
          diagnostics,
          result: {
            modules,
            filters: { prefix: options.prefix, ref: options.ref },
            entries,
            count: entries.length,
          },
        };
      },
      options,
    );
  }

  async decl(declName: string, options: InformalEnvironmentOptions): Promise<InformalCliResponse<InformalDeclResult>> {
    return await this.execute(
      [...modulesArgs(options.modules), "decl", declName],
      (record, diagnostics) => {
        const modules = parseModules(record, diagnostics) ?? [];
        return {
          ok: true,
          command: expectString(record.command, "decl.command", diagnostics),
          modules,
          target: expectString(record.target, "decl.target", diagnostics),
          diagnostics,
          result: {
            modules,
            target: expectString(record.target, "decl.target", diagnostics),
            entry: parseDeclEntry(record.data, diagnostics),
          },
        };
      },
      options,
    );
  }

  async refs(options: InformalRefsOptions): Promise<InformalCliResponse<InformalRefsResult>> {
    const args = [...modulesArgs(options.modules), "refs"];
    if (options.prefix !== undefined) args.push("--prefix", options.prefix);
    return await this.execute(
      args,
      (record, diagnostics) => {
        const data = expectRecord(record.data, "refs.data", diagnostics);
        const entries = expectArray(data.entries, "refs.data.entries", diagnostics).map((item) => parseRefEntry(item, diagnostics));
        const modules = parseModules(record, diagnostics) ?? [];
        return {
          ok: true,
          command: expectString(record.command, "refs.command", diagnostics),
          modules,
          diagnostics,
          result: {
            modules,
            filters: { prefix: options.prefix },
            entries,
            count: entries.length,
          },
        };
      },
      options,
    );
  }

  async ref(ref: string, options: InformalEnvironmentOptions): Promise<InformalCliResponse<InformalRefResult>> {
    return await this.execute(
      [...modulesArgs(options.modules), "ref", ref],
      (record, diagnostics) => {
        const modules = parseModules(record, diagnostics) ?? [];
        return {
          ok: true,
          command: expectString(record.command, "ref.command", diagnostics),
          modules,
          target: expectString(record.target, "ref.target", diagnostics),
          diagnostics,
          result: {
            modules,
            target: expectString(record.target, "ref.target", diagnostics),
            entry: parseRefEntry(record.data, diagnostics),
          },
        };
      },
      options,
    );
  }

  async deps(options: InformalDepsOptions): Promise<InformalCliResponse<InformalDepsResult>> {
    const mode = options.mode ?? "decl";
    const args = [...modulesArgs(options.modules), "deps", "--by", mode];
    if (options.onlyLeaves === true) args.push("--only-leaves");
    return await this.execute<InformalDepsResult>(
      args,
      (record, diagnostics) => {
        const modules = parseModules(record, diagnostics) ?? [];
        const data = expectRecord(record.data, "deps.data", diagnostics);
        const parsedMode = expectString(record.mode, "deps.mode", diagnostics) as "decl" | "ref";
        if (parsedMode === "decl") {
          const rows = expectArray(data.rows, "deps.data.rows", diagnostics).map((item) => {
            const row = expectRecord(item, "deps.data.rows[]", diagnostics);
            return {
              declName: expectString(row.declName, "deps.row.declName", diagnostics),
              dependencies: stringArray(row.dependencies, "deps.row.dependencies", diagnostics),
            } satisfies InformalDeclDependencyRow;
          });
          return {
            ok: true,
            command: expectString(record.command, "deps.command", diagnostics),
            modules,
            mode: parsedMode,
            diagnostics,
            result: {
              modules,
              mode: parsedMode,
              onlyLeaves: options.onlyLeaves ?? false,
              rows,
              leaves: stringArray(data.leaves, "deps.data.leaves", diagnostics),
            },
          };
        }
        const rows = expectArray(data.rows, "deps.data.rows", diagnostics).map((item) => {
          const row = expectRecord(item, "deps.data.rows[]", diagnostics);
          return {
            ref: expectString(row.ref, "deps.row.ref", diagnostics),
            dependencies: stringArray(row.dependencies, "deps.row.dependencies", diagnostics),
          } satisfies InformalReferenceDependencyRow;
        });
        return {
          ok: true,
          command: expectString(record.command, "deps.command", diagnostics),
          modules,
          mode: parsedMode,
          diagnostics,
          result: {
            modules,
            mode: parsedMode,
            onlyLeaves: options.onlyLeaves ?? false,
            rows,
            leaves: stringArray(data.leaves, "deps.data.leaves", diagnostics),
          },
        };
      },
      options,
    );
  }

  async present(ref: string, options: InformalPresentOptions = {}): Promise<InformalCliResponse<InformalPresentResult>> {
    const mode = options.mode ?? "rich";
    const args = [...rootArgs(options.root), "present", ref, "--mode", mode];
    if (mode === "rich" && options.body !== undefined) {
      args.push("--body", options.body);
    }
    return await this.execute<InformalPresentResult>(
      args,
      (record, diagnostics) => {
        const command = expectString(record.command, "present.command", diagnostics);
        const target = expectString(record.target, "present.target", diagnostics);
        const parsedMode = expectString(record.mode, "present.mode", diagnostics) as "compact" | "rich";
        if (parsedMode === "compact") {
          const data = expectRecord(record.data, "present.data", diagnostics);
          return {
            ok: true,
            command,
            target,
            mode: parsedMode,
            diagnostics,
            result: {
              target,
              mode: parsedMode,
              summary: parsePresentationSummary(data.summary, diagnostics),
            },
          };
        }
        return {
          ok: true,
          command,
          target,
          mode: parsedMode,
          bodyMode: expectString(record.bodyMode, "present.bodyMode", diagnostics),
          diagnostics,
          result: {
            target,
            mode: parsedMode,
            bodyMode: expectString(record.bodyMode, "present.bodyMode", diagnostics) as "none" | "preview" | "full",
            payload: parsePresentationPayload(record.data, diagnostics),
          },
        };
      },
      options,
    );
  }
}
