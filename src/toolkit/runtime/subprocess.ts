import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { once } from "node:events";
import {
  ToolkitCancellationError,
  ToolkitLifecycleError,
  ToolkitProcessError,
  ToolkitProcessStartError,
  ToolkitTimeoutError,
} from "./errors.ts";
import { debugRuntimeEvent, type ToolkitRuntimeContext } from "./options.ts";
import type { ResolvedCommandSpec } from "./executables.ts";

export interface CompletedCommand {
  command: ResolvedCommandSpec;
  args: string[];
  cwd: string;
  stdout: string;
  stderr: string;
  exitCode: number | null;
  signal: NodeJS.Signals | null;
  durationMs: number;
  forcedKill: boolean;
}

export interface RunCommandOptions {
  stdinText?: string;
  timeoutMs?: number;
  signal?: AbortSignal;
}

export interface ManagedProcessExitInfo {
  exitCode: number | null;
  signal: NodeJS.Signals | null;
  stderr: string;
}

export interface ManagedSubprocessOptions {
  onStdoutChunk?: (chunk: string) => void;
  onExit?: (info: ManagedProcessExitInfo) => void;
}

export interface ManagedStopOptions {
  gracefulAction?: () => Promise<void>;
  gracefulTimeoutMs?: number;
}

function appendTailWithinBytes(current: string, chunk: string, maxBytes: number): string {
  const combined = current + chunk;
  const combinedBytes = Buffer.byteLength(combined);
  if (combinedBytes <= maxBytes) {
    return combined;
  }

  const buffer = Buffer.from(combined);
  return buffer.subarray(buffer.length - maxBytes).toString("utf8");
}

async function waitForExit(child: ChildProcessWithoutNullStreams, timeoutMs: number): Promise<boolean> {
  if (child.exitCode !== null || child.killed) {
    return true;
  }

  return await new Promise<boolean>((resolve) => {
    const timer = setTimeout(() => {
      child.off("exit", onExit);
      resolve(false);
    }, timeoutMs);

    const onExit = () => {
      clearTimeout(timer);
      resolve(true);
    };

    child.once("exit", onExit);
  });
}

export async function terminateChildProcess(
  child: ChildProcessWithoutNullStreams,
  runtime: ToolkitRuntimeContext,
): Promise<{ forcedKill: boolean }> {
  if (child.exitCode !== null || child.killed) {
    return { forcedKill: false };
  }

  child.kill("SIGTERM");
  const exitedAfterTerm = await waitForExit(child, runtime.timeouts.terminateWaitMs);
  if (exitedAfterTerm) {
    return { forcedKill: false };
  }

  child.kill("SIGKILL");
  await waitForExit(child, runtime.timeouts.killWaitMs);
  return { forcedKill: true };
}

function teeStderr(runtime: ToolkitRuntimeContext, chunk: string): void {
  const sink = runtime.stderrTee;
  if (sink === undefined) {
    return;
  }
  if (typeof sink === "function") {
    sink(chunk);
    return;
  }
  sink.write(chunk);
}

function childLabel(spec: ResolvedCommandSpec, args: string[]): string {
  return `${spec.command} ${args.join(" ")} (cwd: ${spec.cwd})`;
}

async function withOptionalTimeout<T>(promise: Promise<T>, timeoutMs: number | undefined, onTimeout: () => Promise<void>): Promise<T> {
  if (timeoutMs === undefined) {
    return await promise;
  }

  let timer: NodeJS.Timeout | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_resolve, reject) => {
        timer = setTimeout(async () => {
          try {
            await onTimeout();
          } finally {
            reject(new ToolkitTimeoutError(`Operation timed out after ${Math.round(timeoutMs / 1000)}s.`));
          }
        }, timeoutMs);
      }),
    ]);
  } finally {
    if (timer !== undefined) {
      clearTimeout(timer);
    }
  }
}

export class ManagedSubprocess {
  private child: ChildProcessWithoutNullStreams | null = null;
  private startPromise: Promise<void> | null = null;
  private recentStderr = "";
  private readonly runtime: ToolkitRuntimeContext;
  private readonly spec: ResolvedCommandSpec;
  private readonly options: ManagedSubprocessOptions;

  constructor(runtime: ToolkitRuntimeContext, spec: ResolvedCommandSpec, options: ManagedSubprocessOptions = {}) {
    this.runtime = runtime;
    this.spec = spec;
    this.options = options;
  }

  isRunning(): boolean {
    return this.child !== null && this.child.exitCode === null && !this.child.killed;
  }

  getRecentStderr(): string {
    return this.recentStderr;
  }

  getChild(): ChildProcessWithoutNullStreams | null {
    return this.child;
  }

  async start(): Promise<void> {
    if (this.isRunning()) {
      return;
    }
    if (this.startPromise !== null) {
      await this.startPromise;
      return;
    }

    this.startPromise = new Promise<void>((resolve, reject) => {
      let spawned = false;
      const args = [...this.spec.args];
      const child = spawn(this.spec.command, args, {
        cwd: this.spec.cwd,
        env: this.spec.env,
        stdio: ["pipe", "pipe", "pipe"],
      });

      if (child.stdin === null || child.stdout === null || child.stderr === null) {
        reject(
          new ToolkitProcessStartError(`Failed to start ${childLabel(this.spec, args)}: missing stdio pipes.`, {
            commandLabel: this.spec.label,
            cwd: this.spec.cwd,
          }),
        );
        return;
      }

      this.child = child;
      this.recentStderr = "";
      child.stdout.setEncoding(this.runtime.capture.encoding);
      child.stderr.setEncoding(this.runtime.capture.encoding);

      child.stdout.on("data", (chunk: string) => {
        this.options.onStdoutChunk?.(chunk);
      });

      child.stderr.on("data", (chunk: string) => {
        this.recentStderr = appendTailWithinBytes(
          this.recentStderr,
          chunk,
          this.runtime.capture.maxManagedStderrBytes,
        );
        teeStderr(this.runtime, chunk);
      });

      child.once("spawn", () => {
        spawned = true;
        debugRuntimeEvent(this.runtime, "managed_process_spawn", `Started ${this.spec.label}.`);
        resolve();
      });

      child.on("error", (error) => {
        const wrapped = new ToolkitProcessStartError(`Managed process error for ${this.spec.label}: ${error.message}`, {
          commandLabel: this.spec.label,
          cwd: this.spec.cwd,
          stderr: this.recentStderr,
        });
        if (!spawned) {
          reject(wrapped);
          return;
        }
        this.options.onExit?.({
          exitCode: child.exitCode,
          signal: null,
          stderr: this.recentStderr,
        });
      });

      child.on("exit", (code, signal) => {
        if (this.child === child) {
          this.child = null;
        }
        const exitInfo: ManagedProcessExitInfo = {
          exitCode: code,
          signal,
          stderr: this.recentStderr,
        };
        this.options.onExit?.(exitInfo);
        if (!spawned) {
          reject(
            new ToolkitProcessStartError(
              `Failed to start ${this.spec.label}: process exited before startup completed.`,
              {
                commandLabel: this.spec.label,
                cwd: this.spec.cwd,
                exitCode: code,
                signal,
                stderr: this.recentStderr,
              },
            ),
          );
        }
      });
    }).finally(() => {
      this.startPromise = null;
    });

    await this.startPromise;
  }

  async write(data: string): Promise<void> {
    const child = this.child;
    if (child === null || child.stdin.destroyed || !this.isRunning()) {
      throw new ToolkitLifecycleError(`Managed process is not running: ${this.spec.label}.`, {
        commandLabel: this.spec.label,
        cwd: this.spec.cwd,
        stderr: this.recentStderr,
      });
    }

    await new Promise<void>((resolve, reject) => {
      child.stdin.write(data, this.runtime.capture.encoding, (error) => {
        if (error !== null && error !== undefined) {
          reject(
            new ToolkitLifecycleError(`Failed to write to managed process ${this.spec.label}: ${error.message}`, {
              commandLabel: this.spec.label,
              cwd: this.spec.cwd,
              stderr: this.recentStderr,
            }),
          );
          return;
        }
        resolve();
      });
    });
  }

  async stop(options: ManagedStopOptions = {}): Promise<void> {
    const child = this.child;
    if (child === null) {
      return;
    }

    if (options.gracefulAction !== undefined && this.isRunning()) {
      try {
        await withOptionalTimeout(options.gracefulAction(), options.gracefulTimeoutMs, async () => {
          await Promise.resolve();
        });
      } catch {
        // Fall through to explicit termination.
      }
    }

    await terminateChildProcess(child, this.runtime);
    if (this.child === child) {
      this.child = null;
    }
  }
}

export async function runCommand(
  runtime: ToolkitRuntimeContext,
  spec: ResolvedCommandSpec,
  extraArgs: string[],
  options: RunCommandOptions = {},
): Promise<CompletedCommand> {
  const args = [...spec.args, ...extraArgs];
  const label = childLabel(spec, args);
  const startTime = Date.now();
  const timeoutMs = options.timeoutMs ?? runtime.timeouts.operationMs;

  if (options.signal?.aborted === true) {
    throw new ToolkitCancellationError(`Command cancelled before start: ${label}.`, {
      commandLabel: spec.label,
      cwd: spec.cwd,
    });
  }

  return await new Promise<CompletedCommand>((resolve, reject) => {
    let stdout = "";
    let stderr = "";
    let stdoutBytes = 0;
    let settled = false;
    let forcedKill = false;
    let spawned = false;
    let timeoutHandle: NodeJS.Timeout | undefined;

    const child = spawn(spec.command, args, {
      cwd: spec.cwd,
      env: spec.env,
      stdio: ["pipe", "pipe", "pipe"],
    });

    const cleanup = (): void => {
      if (timeoutHandle !== undefined) {
        clearTimeout(timeoutHandle);
      }
      if (options.signal !== undefined) {
        options.signal.removeEventListener("abort", onAbort);
      }
    };

    const finalizeSuccess = (exitCode: number | null, signal: NodeJS.Signals | null): void => {
      if (settled) {
        return;
      }
      settled = true;
      cleanup();
      resolve({
        command: spec,
        args,
        cwd: spec.cwd,
        stdout,
        stderr,
        exitCode,
        signal,
        durationMs: Date.now() - startTime,
        forcedKill,
      });
    };

    const finalizeError = async (error: Error): Promise<void> => {
      if (settled) {
        return;
      }
      settled = true;
      cleanup();
      const termination = await terminateChildProcess(child, runtime);
      forcedKill = termination.forcedKill;
      reject(error);
    };

    const onAbort = (): void => {
      void finalizeError(
        new ToolkitCancellationError(`Command cancelled: ${label}.`, {
          commandLabel: spec.label,
          cwd: spec.cwd,
          stdout,
          stderr,
          durationMs: Date.now() - startTime,
        }),
      );
    };

    if (child.stdin === null || child.stdout === null || child.stderr === null) {
      cleanup();
      reject(
        new ToolkitProcessStartError(`Failed to start ${label}: missing stdio pipes.`, {
          commandLabel: spec.label,
          cwd: spec.cwd,
        }),
      );
      return;
    }

    child.stdout.setEncoding(runtime.capture.encoding);
    child.stderr.setEncoding(runtime.capture.encoding);

    child.once("spawn", () => {
      spawned = true;
      debugRuntimeEvent(runtime, "command_spawn", `Started ${label}.`);
      if (options.stdinText !== undefined) {
        child.stdin.end(options.stdinText, runtime.capture.encoding);
      } else {
        child.stdin.end();
      }
    });

    child.on("error", (error) => {
      if (!spawned) {
        cleanup();
        reject(
          new ToolkitProcessStartError(`Failed to start ${label}: ${error.message}`, {
            commandLabel: spec.label,
            cwd: spec.cwd,
            stdout,
            stderr,
          }),
        );
        return;
      }
      void finalizeError(
        new ToolkitProcessError(`Command failed while running ${label}: ${error.message}`, {
          commandLabel: spec.label,
          cwd: spec.cwd,
          stdout,
          stderr,
          durationMs: Date.now() - startTime,
        }),
      );
    });

    child.stdout.on("data", (chunk: string) => {
      if (settled) {
        return;
      }
      stdoutBytes += Buffer.byteLength(chunk);
      if (stdoutBytes > runtime.capture.maxCommandStdoutBytes) {
        void finalizeError(
          new ToolkitProcessError(`Command output exceeded the configured stdout limit: ${label}.`, {
            commandLabel: spec.label,
            cwd: spec.cwd,
            stdout,
            stderr,
            durationMs: Date.now() - startTime,
          }),
        );
        return;
      }
      stdout += chunk;
    });

    child.stderr.on("data", (chunk: string) => {
      if (settled) {
        return;
      }
      stderr = appendTailWithinBytes(stderr, chunk, runtime.capture.maxCommandStderrBytes);
      teeStderr(runtime, chunk);
    });

    child.on("exit", (exitCode, signal) => {
      finalizeSuccess(exitCode, signal);
    });

    timeoutHandle = setTimeout(() => {
      void finalizeError(
        new ToolkitTimeoutError(`Command timed out after ${Math.round(timeoutMs / 1000)}s: ${label}.`, {
          commandLabel: spec.label,
          cwd: spec.cwd,
          stdout,
          stderr,
          durationMs: Date.now() - startTime,
        }),
      );
    }, timeoutMs);

    options.signal?.addEventListener("abort", onAbort, { once: true });
  });
}

export async function waitForProcessExit(child: ChildProcessWithoutNullStreams): Promise<void> {
  if (child.exitCode !== null) {
    return;
  }
  await once(child, "exit");
}
