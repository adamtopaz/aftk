import {
  ToolkitCancellationError,
  ToolkitLifecycleError,
  ToolkitProcessError,
  ToolkitProtocolError,
  ToolkitTimeoutError,
} from "../runtime/errors.ts";
import { ManagedSubprocess } from "../runtime/subprocess.ts";
import {
  createToolkitRuntimeContext,
  type ToolkitRuntimeContext,
  type ToolkitRuntimeOptions,
} from "../runtime/options.ts";
import {
  validateMethodResult,
  type AftkServerMethod,
  type OpenParams,
  type OpenResult,
  type CloseParams,
  type CloseResult,
  type FileLocationParams,
  type FileNodeParams,
  type RunTacticParams,
  type RunTacticStepsParams,
  type ShutdownResult,
  type ShutdownParams,
  type HoverResult,
  type PlainGoalResult,
  type PlainTermGoalResult,
  type InfoViewResult,
  type LoadNodeResult,
  type GetGoalsResult,
  type RunTacticResult,
  type RunTacticStepsResult,
  type ParamsFor,
  type ResultFor,
} from "./protocol.ts";
import type { ToolkitDiagnostics } from "../output/result.ts";

export interface AftkServerRequestOptions {
  timeoutMs?: number;
  signal?: AbortSignal;
  autoStart?: boolean;
}

interface PendingRequest {
  method: AftkServerMethod;
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
  timeout: NodeJS.Timeout;
  cleanupAbort: () => void;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export class AftkServerRpcError extends Error {
  readonly method: AftkServerMethod;
  readonly code: number;
  readonly data: unknown;
  readonly diagnostics?: ToolkitDiagnostics;

  constructor(
    method: AftkServerMethod,
    code: number,
    message: string,
    data?: unknown,
    diagnostics?: ToolkitDiagnostics,
  ) {
    super(message);
    this.name = "AftkServerRpcError";
    this.method = method;
    this.code = code;
    this.data = data;
    this.diagnostics = diagnostics;
  }
}

export class AftkServerProtocolError extends ToolkitProtocolError {
  readonly diagnostics?: ToolkitDiagnostics;

  constructor(message: string, diagnostics?: ToolkitDiagnostics, data?: unknown) {
    super(message, { ...diagnostics, data });
    this.name = "AftkServerProtocolError";
    this.diagnostics = diagnostics;
  }
}

export function isAftkServerRpcError(error: unknown): error is AftkServerRpcError {
  return error instanceof AftkServerRpcError;
}

export interface CreateAftkServerClientOptions extends ToolkitRuntimeOptions {
  runtime?: ToolkitRuntimeContext;
}

export class AftkServerClient {
  readonly runtime: ToolkitRuntimeContext;

  private readonly process: ManagedSubprocess;
  private stdoutBuffer = "";
  private nextId = 1;
  private readonly pending = new Map<string, PendingRequest>();

  constructor(options: CreateAftkServerClientOptions = {}) {
    this.runtime = options.runtime ?? createToolkitRuntimeContext(options);
    this.process = new ManagedSubprocess(this.runtime, this.runtime.executables.hub, {
      onStdoutChunk: (chunk) => this.onStdoutChunk(chunk),
      onExit: (info) => {
        this.stdoutBuffer = "";
        this.rejectAllPending(
          new ToolkitProcessError(`AFTK hub exited unexpectedly.`, {
            commandLabel: this.runtime.executables.hub.label,
            cwd: this.runtime.executables.hub.cwd,
            exitCode: info.exitCode,
            signal: info.signal,
            stderr: info.stderr,
          }),
        );
      },
    });
  }

  async start(): Promise<void> {
    await this.process.start();
  }

  isRunning(): boolean {
    return this.process.isRunning();
  }

  private currentDiagnostics(): ToolkitDiagnostics {
    return {
      stderr: this.process.getRecentStderr(),
    };
  }

  private onStdoutChunk(chunk: string): void {
    this.stdoutBuffer += chunk;
    while (true) {
      const newlineIndex = this.stdoutBuffer.indexOf("\n");
      if (newlineIndex < 0) {
        return;
      }
      const line = this.stdoutBuffer.slice(0, newlineIndex).trim();
      this.stdoutBuffer = this.stdoutBuffer.slice(newlineIndex + 1);
      if (line.length === 0) {
        continue;
      }
      this.onResponseLine(line);
    }
  }

  private rejectAllPending(error: Error): void {
    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timeout);
      pending.cleanupAbort();
      this.pending.delete(id);
      pending.reject(error);
    }
  }

  private handleProtocolCorruption(message: string, rawData: unknown): void {
    const error = new AftkServerProtocolError(message, this.currentDiagnostics(), rawData);
    this.rejectAllPending(error);
    void this.process.stop();
  }

  private onResponseLine(line: string): void {
    let parsed: unknown;
    try {
      parsed = JSON.parse(line);
    } catch {
      this.handleProtocolCorruption(`AFTK hub emitted malformed JSON-RPC output.`, line);
      return;
    }

    if (!isRecord(parsed)) {
      this.handleProtocolCorruption(`AFTK hub emitted a non-object JSON-RPC response.`, parsed);
      return;
    }
    if (parsed.jsonrpc !== "2.0") {
      this.handleProtocolCorruption(`AFTK hub emitted a response with an invalid jsonrpc version.`, parsed);
      return;
    }
    if (!("id" in parsed)) {
      this.handleProtocolCorruption(`AFTK hub emitted a response without an id.`, parsed);
      return;
    }

    const id = String(parsed.id);
    const pending = this.pending.get(id);
    if (pending === undefined) {
      return;
    }

    const hasResult = "result" in parsed;
    const hasError = "error" in parsed;
    if (hasResult === hasError) {
      this.pending.delete(id);
      clearTimeout(pending.timeout);
      pending.cleanupAbort();
      pending.reject(
        new AftkServerProtocolError(
          `AFTK hub emitted an invalid JSON-RPC envelope for '${pending.method}'.`,
          this.currentDiagnostics(),
          parsed,
        ),
      );
      return;
    }

    this.pending.delete(id);
    clearTimeout(pending.timeout);
    pending.cleanupAbort();

    if (hasError) {
      const errorValue = parsed.error;
      if (!isRecord(errorValue) || typeof errorValue.code !== "number" || typeof errorValue.message !== "string") {
        pending.reject(
          new AftkServerProtocolError(
            `AFTK hub emitted an invalid JSON-RPC error payload for '${pending.method}'.`,
            this.currentDiagnostics(),
            parsed,
          ),
        );
        return;
      }
      pending.reject(
        new AftkServerRpcError(
          pending.method,
          errorValue.code,
          errorValue.message,
          errorValue.data,
          this.currentDiagnostics(),
        ),
      );
      return;
    }

    if (!validateMethodResult(pending.method, parsed.result)) {
      pending.reject(
        new AftkServerProtocolError(
          `AFTK hub returned an invalid result shape for '${pending.method}'.`,
          this.currentDiagnostics(),
          parsed.result,
        ),
      );
      return;
    }

    pending.resolve(parsed.result);
  }

  async request<M extends AftkServerMethod>(
    method: M,
    params: ParamsFor<M>,
    options: AftkServerRequestOptions = {},
  ): Promise<ResultFor<M>> {
    const autoStart = options.autoStart ?? true;
    const timeoutMs = options.timeoutMs ?? this.runtime.timeouts.operationMs;

    if (autoStart) {
      await this.start();
    }

    if (!this.isRunning()) {
      throw new ToolkitLifecycleError(`AFTK hub is not running.`, {
        commandLabel: this.runtime.executables.hub.label,
        cwd: this.runtime.executables.hub.cwd,
        stderr: this.process.getRecentStderr(),
      });
    }

    const child = this.process.getChild();
    if (child === null || child.stdin.destroyed) {
      throw new ToolkitLifecycleError(`AFTK hub stdin is unavailable.`, {
        commandLabel: this.runtime.executables.hub.label,
        cwd: this.runtime.executables.hub.cwd,
        stderr: this.process.getRecentStderr(),
      });
    }

    const id = this.nextId++;
    const idKey = String(id);
    const payload = `${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`;

    return await new Promise<ResultFor<M>>((resolve, reject) => {
      const cleanupAbort = (): void => {
        if (options.signal !== undefined) {
          options.signal.removeEventListener("abort", onAbort);
        }
      };

      const rejectIfPending = (error: Error): void => {
        const pending = this.pending.get(idKey);
        if (pending === undefined) {
          return;
        }
        this.pending.delete(idKey);
        clearTimeout(pending.timeout);
        pending.cleanupAbort();
        reject(error);
      };

      const timeout = setTimeout(() => {
        rejectIfPending(
          new ToolkitTimeoutError(`AFTK hub request timed out after ${Math.round(timeoutMs / 1000)}s: ${method}.`, {
            commandLabel: this.runtime.executables.hub.label,
            cwd: this.runtime.executables.hub.cwd,
            stderr: this.process.getRecentStderr(),
            data: { method },
          }),
        );
      }, timeoutMs);

      const onAbort = (): void => {
        rejectIfPending(
          new ToolkitCancellationError(`AFTK hub request was cancelled: ${method}.`, {
            commandLabel: this.runtime.executables.hub.label,
            cwd: this.runtime.executables.hub.cwd,
            stderr: this.process.getRecentStderr(),
            data: { method, cancelled: true },
          }),
        );
      };

      if (options.signal !== undefined) {
        if (options.signal.aborted) {
          clearTimeout(timeout);
          reject(
            new ToolkitCancellationError(`AFTK hub request was cancelled before it was sent: ${method}.`, {
              commandLabel: this.runtime.executables.hub.label,
              cwd: this.runtime.executables.hub.cwd,
              stderr: this.process.getRecentStderr(),
              data: { method, cancelled: true },
            }),
          );
          return;
        }
        options.signal.addEventListener("abort", onAbort, { once: true });
      }

      this.pending.set(idKey, {
        method,
        resolve: (value) => resolve(value as ResultFor<M>),
        reject,
        timeout,
        cleanupAbort,
      });

      child.stdin.write(payload, this.runtime.capture.encoding, (error) => {
        if (error === null || error === undefined) {
          return;
        }
        rejectIfPending(
          new ToolkitLifecycleError(`Failed to send '${method}' to the AFTK hub: ${error.message}`, {
            commandLabel: this.runtime.executables.hub.label,
            cwd: this.runtime.executables.hub.cwd,
            stderr: this.process.getRecentStderr(),
          }),
        );
      });
    });
  }

  async open(params: OpenParams, options?: AftkServerRequestOptions): Promise<OpenResult> {
    return await this.request("open", params, options);
  }

  async close(params: CloseParams, options?: AftkServerRequestOptions): Promise<CloseResult> {
    return await this.request("close", params, options);
  }

  async loadNode(params: FileLocationParams, options?: AftkServerRequestOptions): Promise<LoadNodeResult> {
    return await this.request("load_node", params, options);
  }

  async getHover(params: FileLocationParams, options?: AftkServerRequestOptions): Promise<HoverResult | null> {
    return await this.request("get_hover", params, options);
  }

  async getPlainGoal(
    params: FileLocationParams,
    options?: AftkServerRequestOptions,
  ): Promise<PlainGoalResult | null> {
    return await this.request("get_plain_goal", params, options);
  }

  async getPlainTermGoal(
    params: FileLocationParams,
    options?: AftkServerRequestOptions,
  ): Promise<PlainTermGoalResult | null> {
    return await this.request("get_plain_term_goal", params, options);
  }

  async getInfoView(params: FileLocationParams, options?: AftkServerRequestOptions): Promise<InfoViewResult> {
    return await this.request("get_infoview", params, options);
  }

  async getGoals(params: FileNodeParams, options?: AftkServerRequestOptions): Promise<GetGoalsResult> {
    return await this.request("get_goals", params, options);
  }

  async runTactic(params: RunTacticParams, options?: AftkServerRequestOptions): Promise<RunTacticResult> {
    return await this.request("run_tactic", params, options);
  }

  async runTacticSteps(
    params: RunTacticStepsParams,
    options?: AftkServerRequestOptions,
  ): Promise<RunTacticStepsResult> {
    return await this.request("run_tactic_steps", params, options);
  }

  async shutdown(options?: AftkServerRequestOptions): Promise<ShutdownResult> {
    if (!this.isRunning()) {
      return { stopped: 0 };
    }
    const result = await this.request("shutdown", {} satisfies ShutdownParams, {
      ...options,
      autoStart: false,
      timeoutMs: options?.timeoutMs ?? this.runtime.timeouts.shutdownMs,
    });
    await this.stop(false);
    return result;
  }

  async stop(graceful = true): Promise<void> {
    await this.process.stop({
      gracefulAction:
        graceful && this.isRunning()
          ? async () => {
              try {
                await this.request("shutdown", {} satisfies ShutdownParams, {
                  autoStart: false,
                  timeoutMs: this.runtime.timeouts.shutdownMs,
                });
              } catch {
                // Fall back to explicit process termination.
              }
            }
          : undefined,
      gracefulTimeoutMs: this.runtime.timeouts.shutdownMs,
    });
  }
}
