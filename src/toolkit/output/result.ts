import {
  isToolkitRuntimeError,
  ToolkitCancellationError,
  ToolkitProtocolError,
  ToolkitTimeoutError,
} from "../runtime/errors.ts";
import { truncateText, type ToolkitTextTruncationInfo } from "./truncate.ts";

export type ToolkitFamily = "lean" | "knowledgebase" | "informal";

export interface ToolkitWarning {
  message: string;
  code?: string;
  source?: string;
}

export interface ToolkitDiagnostics {
  stderr?: string;
  stdout?: string;
  exitCode?: number | null;
  signal?: NodeJS.Signals | null;
  durationMs?: number;
  forcedKill?: boolean;
  raw?: unknown;
}

export interface ToolkitTruncationInfo extends ToolkitTextTruncationInfo {
  detailsTruncated?: boolean;
  fields?: string[];
}

export type ToolkitBackendInfo =
  | {
      kind: "server";
      method: string;
      exitCode?: number | null;
    }
  | {
      kind: "knowledgebase_cli";
      command: string;
      root?: string;
      exitCode?: number | null;
    }
  | {
      kind: "informal_cli";
      command: string;
      root?: string;
      modules?: string[];
      exitCode?: number | null;
    };

export type ToolkitErrorKind = "rpc" | "cli" | "runtime" | "protocol" | "timeout" | "cancelled";

export interface ToolkitToolError {
  kind: ToolkitErrorKind;
  category: string;
  message: string;
  code?: string | number;
  data?: unknown;
}

export interface ToolkitSuccessDetails<T = unknown> {
  ok: true;
  tool: string;
  family: ToolkitFamily;
  backend: ToolkitBackendInfo;
  result: T;
  warnings: ToolkitWarning[];
  truncation?: ToolkitTruncationInfo;
  diagnostics?: ToolkitDiagnostics;
}

export interface ToolkitFailureDetails {
  ok: false;
  tool: string;
  family: ToolkitFamily;
  backend: ToolkitBackendInfo;
  error: ToolkitToolError;
  warnings: ToolkitWarning[];
  truncation?: ToolkitTruncationInfo;
  diagnostics?: ToolkitDiagnostics;
}

export type ToolkitToolDetails<T = unknown> = ToolkitSuccessDetails<T> | ToolkitFailureDetails;

export interface ToolkitToolContent {
  type: "text";
  text: string;
}

export interface ToolkitToolResult<T = unknown> {
  content: [ToolkitToolContent];
  details: ToolkitToolDetails<T>;
  isError?: boolean;
}

export interface BuildSuccessResultOptions<T> {
  tool: string;
  family: ToolkitFamily;
  backend: ToolkitBackendInfo;
  text: string;
  result: T;
  warnings?: ToolkitWarning[];
  diagnostics?: ToolkitDiagnostics;
}

export interface BuildFailureResultOptions {
  tool: string;
  family: ToolkitFamily;
  backend: ToolkitBackendInfo;
  text: string;
  error: ToolkitToolError;
  warnings?: ToolkitWarning[];
  diagnostics?: ToolkitDiagnostics;
}

export function buildSuccessResult<T>(options: BuildSuccessResultOptions<T>): ToolkitToolResult<T> {
  const truncated = truncateText(options.text);
  return {
    content: [{ type: "text", text: truncated.text }],
    details: {
      ok: true,
      tool: options.tool,
      family: options.family,
      backend: options.backend,
      result: options.result,
      warnings: options.warnings ?? [],
      truncation: truncated.truncation,
      diagnostics: options.diagnostics,
    },
  };
}

export function buildFailureResult(options: BuildFailureResultOptions): ToolkitToolResult<never> {
  const truncated = truncateText(options.text);
  return {
    content: [{ type: "text", text: truncated.text }],
    details: {
      ok: false,
      tool: options.tool,
      family: options.family,
      backend: options.backend,
      error: options.error,
      warnings: options.warnings ?? [],
      truncation: truncated.truncation,
      diagnostics: options.diagnostics,
    },
    isError: true,
  };
}

export function diagnosticsFromRuntimeLike(error: unknown): ToolkitDiagnostics | undefined {
  if (!isToolkitRuntimeError(error)) {
    return undefined;
  }
  return {
    stderr: error.details.stderr,
    stdout: error.details.stdout,
    exitCode: error.details.exitCode,
    signal: error.details.signal,
    durationMs: error.details.durationMs,
    forcedKill: error.details.forcedKill,
    raw: error.details.data,
  };
}

export function toolErrorFromUnknown(error: unknown, category = "runtime"): ToolkitToolError {
  if (error instanceof ToolkitTimeoutError) {
    return {
      kind: "timeout",
      category: "timeout",
      message: error.message,
    };
  }
  if (error instanceof ToolkitCancellationError) {
    return {
      kind: "cancelled",
      category: "cancelled",
      message: error.message,
    };
  }
  if (error instanceof ToolkitProtocolError) {
    return {
      kind: "protocol",
      category: "protocol",
      message: error.message,
      data: error.details.data,
    };
  }
  if (isToolkitRuntimeError(error)) {
    return {
      kind: "runtime",
      category,
      message: error.message,
      data: error.details.data,
    };
  }
  if (error instanceof Error) {
    return {
      kind: "runtime",
      category,
      message: error.message,
    };
  }
  return {
    kind: "runtime",
    category,
    message: String(error),
  };
}

export function cliCategoryFromExitCode(exitCode: number | null | undefined): string {
  switch (exitCode) {
    case 2:
      return "usage";
    case 3:
      return "not_found";
    case 4:
      return "validation";
    case 5:
      return "conflict";
    default:
      return "operational";
  }
}
