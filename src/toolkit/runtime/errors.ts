export type ToolkitRuntimeErrorKind =
  | "config"
  | "start"
  | "process"
  | "timeout"
  | "cancelled"
  | "lifecycle"
  | "protocol";

export interface ToolkitRuntimeErrorDetails {
  operation?: string;
  commandLabel?: string;
  cwd?: string;
  exitCode?: number | null;
  signal?: NodeJS.Signals | null;
  stdout?: string;
  stderr?: string;
  durationMs?: number;
  forcedKill?: boolean;
  data?: unknown;
}

export class ToolkitRuntimeError extends Error {
  readonly kind: ToolkitRuntimeErrorKind;
  readonly details: ToolkitRuntimeErrorDetails;

  constructor(kind: ToolkitRuntimeErrorKind, message: string, details: ToolkitRuntimeErrorDetails = {}) {
    super(message);
    this.name = "ToolkitRuntimeError";
    this.kind = kind;
    this.details = details;
  }
}

export class ToolkitConfigError extends ToolkitRuntimeError {
  constructor(message: string, details: ToolkitRuntimeErrorDetails = {}) {
    super("config", message, details);
    this.name = "ToolkitConfigError";
  }
}

export class ToolkitProcessStartError extends ToolkitRuntimeError {
  constructor(message: string, details: ToolkitRuntimeErrorDetails = {}) {
    super("start", message, details);
    this.name = "ToolkitProcessStartError";
  }
}

export class ToolkitProcessError extends ToolkitRuntimeError {
  constructor(message: string, details: ToolkitRuntimeErrorDetails = {}) {
    super("process", message, details);
    this.name = "ToolkitProcessError";
  }
}

export class ToolkitTimeoutError extends ToolkitRuntimeError {
  constructor(message: string, details: ToolkitRuntimeErrorDetails = {}) {
    super("timeout", message, details);
    this.name = "ToolkitTimeoutError";
  }
}

export class ToolkitCancellationError extends ToolkitRuntimeError {
  constructor(message: string, details: ToolkitRuntimeErrorDetails = {}) {
    super("cancelled", message, details);
    this.name = "ToolkitCancellationError";
  }
}

export class ToolkitLifecycleError extends ToolkitRuntimeError {
  constructor(message: string, details: ToolkitRuntimeErrorDetails = {}) {
    super("lifecycle", message, details);
    this.name = "ToolkitLifecycleError";
  }
}

export class ToolkitProtocolError extends ToolkitRuntimeError {
  constructor(message: string, details: ToolkitRuntimeErrorDetails = {}) {
    super("protocol", message, details);
    this.name = "ToolkitProtocolError";
  }
}

export function isToolkitRuntimeError(error: unknown): error is ToolkitRuntimeError {
  return error instanceof ToolkitRuntimeError;
}
