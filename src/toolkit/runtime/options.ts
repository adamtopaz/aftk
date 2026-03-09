import * as path from "node:path";
import {
  resolveToolkitExecutableSpecs,
  type ToolkitExecutableOverrides,
  type ToolkitExecutableSpecs,
} from "./executables.ts";
import { resolveProjectRoot } from "./project-root.ts";

export interface ToolkitTimeoutPolicy {
  operationMs: number;
  shutdownMs: number;
  terminateWaitMs: number;
  killWaitMs: number;
}

export interface ToolkitCapturePolicy {
  maxCommandStdoutBytes: number;
  maxCommandStderrBytes: number;
  maxManagedStderrBytes: number;
  encoding: BufferEncoding;
}

export interface ToolkitDebugEvent {
  type: string;
  message: string;
  data?: unknown;
}

export interface ToolkitRuntimeOptions {
  cwd?: string;
  projectRoot?: string;
  env?: NodeJS.ProcessEnv;
  executables?: Partial<ToolkitExecutableOverrides>;
  timeouts?: Partial<ToolkitTimeoutPolicy>;
  capture?: Partial<ToolkitCapturePolicy>;
  debugSink?: (event: ToolkitDebugEvent) => void;
  stderrTee?: ((chunk: string) => void) | NodeJS.WritableStream;
}

export interface ToolkitRuntimeContext {
  cwd: string;
  projectRoot: string;
  env: NodeJS.ProcessEnv;
  executables: ToolkitExecutableSpecs;
  timeouts: ToolkitTimeoutPolicy;
  capture: ToolkitCapturePolicy;
  debugSink?: (event: ToolkitDebugEvent) => void;
  stderrTee?: ((chunk: string) => void) | NodeJS.WritableStream;
}

export const DEFAULT_TIMEOUT_POLICY: ToolkitTimeoutPolicy = {
  operationMs: 120_000,
  shutdownMs: 5_000,
  terminateWaitMs: 1_500,
  killWaitMs: 1_500,
};

export const DEFAULT_CAPTURE_POLICY: ToolkitCapturePolicy = {
  maxCommandStdoutBytes: 5 * 1024 * 1024,
  maxCommandStderrBytes: 256 * 1024,
  maxManagedStderrBytes: 256 * 1024,
  encoding: "utf8",
};

export function createToolkitRuntimeContext(options: ToolkitRuntimeOptions = {}): ToolkitRuntimeContext {
  const cwd = path.resolve(options.cwd ?? process.cwd());
  const projectRoot = resolveProjectRoot({ cwd, projectRoot: options.projectRoot });
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    ...options.env,
  };

  return {
    cwd,
    projectRoot,
    env,
    executables: resolveToolkitExecutableSpecs({
      cwd,
      projectRoot,
      env,
      overrides: options.executables,
    }),
    timeouts: {
      ...DEFAULT_TIMEOUT_POLICY,
      ...options.timeouts,
    },
    capture: {
      ...DEFAULT_CAPTURE_POLICY,
      ...options.capture,
    },
    debugSink: options.debugSink,
    stderrTee: options.stderrTee,
  };
}

export function debugRuntimeEvent(runtime: ToolkitRuntimeContext, type: string, message: string, data?: unknown): void {
  runtime.debugSink?.({ type, message, data });
}
