import {
  CURRENT_SESSION_VERSION,
  type AgentEndEvent,
  type ExtensionContext,
  type SessionEntry,
  type SessionForkEvent,
  type SessionHeader,
  type SessionShutdownEvent,
  type SessionStartEvent,
  type SessionSwitchEvent,
} from "@mariozechner/pi-coding-agent";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { mkdirSync, renameSync, writeFileSync } from "node:fs";

export interface AftkPiUsageTotals {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  total: number;
}

export interface AftkPiModelRunSummary {
  assistantMessages: number;
  toolCalls: number;
  tokens: AftkPiUsageTotals;
  cost: AftkPiUsageTotals;
}

export interface AftkPiRunTotals {
  prompts: number;
  assistantMessages: number;
  toolCalls: number;
  toolResults: number;
  tokens: AftkPiUsageTotals;
  cost: AftkPiUsageTotals;
}

export interface AftkPiRunCostSummary {
  schemaVersion: 1;
  runId: string;
  cwd: string;
  startedAt: string;
  updatedAt: string;
  endedAt?: string;
  sessionId: string;
  sessionIds: string[];
  sessionFile: string;
  sessionFiles: string[];
  nativeSessionFile: string | null;
  nativeSessionFiles: string[];
  logMode: "native" | "mirror";
  persisted: boolean;
  runTotals: AftkPiRunTotals;
  byModel: Record<string, AftkPiModelRunSummary>;
}

export interface AftkPiLoggingOptions {
  now?: () => Date;
  pid?: number;
  randomSuffix?: () => string;
}

export interface AftkPiLoggingController {
  getSummary(): AftkPiRunCostSummary | undefined;
  flush(): void;
}

export interface AftkPiSessionDirectoryEvent {
  type: "session_directory";
  cwd: string;
}

export interface AftkPiSessionDirectoryResult {
  sessionDir?: string;
}

export interface AftkPiLoggingExtensionAPI {
  on(event: "session_directory", handler: (event: AftkPiSessionDirectoryEvent) => Promise<AftkPiSessionDirectoryResult | void> | AftkPiSessionDirectoryResult | void): void;
  on(event: "session_start", handler: (event: SessionStartEvent, ctx: ExtensionContext) => Promise<void> | void): void;
  on(event: "session_switch", handler: (event: SessionSwitchEvent, ctx: ExtensionContext) => Promise<void> | void): void;
  on(event: "session_fork", handler: (event: SessionForkEvent, ctx: ExtensionContext) => Promise<void> | void): void;
  on(event: "agent_end", handler: (event: AgentEndEvent, ctx: ExtensionContext) => Promise<void> | void): void;
  on(event: "session_shutdown", handler: (event: SessionShutdownEvent, ctx: ExtensionContext) => Promise<void> | void): void;
}

interface SessionLogRef {
  sessionId: string;
  nativeSessionFile: string | undefined;
  logFile: string;
  logMode: "native" | "mirror";
}

interface MutableRunState {
  summary: AftkPiRunCostSummary;
  costFile: string;
}

const SUMMARY_SCHEMA_VERSION = 1;

export function createUsageTotals(): AftkPiUsageTotals {
  return {
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
    total: 0,
  };
}

export function createRunTotals(): AftkPiRunTotals {
  return {
    prompts: 0,
    assistantMessages: 0,
    toolCalls: 0,
    toolResults: 0,
    tokens: createUsageTotals(),
    cost: createUsageTotals(),
  };
}

export function sanitizeFileToken(value: string): string {
  const sanitized = value.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");
  return sanitized.length > 0 ? sanitized : "unnamed";
}

export function createRunId(now: Date = new Date(), pid: number = process.pid, suffix?: string): string {
  const timestamp = sanitizeFileToken(now.toISOString());
  const suffixText = suffix !== undefined && suffix.length > 0 ? `-${sanitizeFileToken(suffix)}` : "";
  return `run-${timestamp}-pid${pid}${suffixText}`;
}

export function resolveLogsDir(cwd: string): string {
  return resolve(cwd, ".aftk", "logs");
}

export function resolveCostDir(cwd: string): string {
  return resolve(cwd, ".aftk", "cost");
}

export function resolveRunCostFile(cwd: string, runId: string): string {
  return join(resolveCostDir(cwd), `${sanitizeFileToken(runId)}.json`);
}

export function resolveMirroredSessionLogFile(cwd: string, sessionId: string): string {
  return join(resolveLogsDir(cwd), `mirror-session-${sanitizeFileToken(sessionId)}.jsonl`);
}

export function projectPath(cwd: string, target: string | undefined): string | null {
  if (target === undefined) {
    return null;
  }
  const absoluteTarget = isAbsolute(target) ? target : resolve(cwd, target);
  const rel = relative(cwd, absoluteTarget);
  if (rel.length > 0 && !rel.startsWith("..") && !isAbsolute(rel)) {
    return rel.replace(/\\/g, "/");
  }
  return absoluteTarget.replace(/\\/g, "/");
}

function isInsideDir(parentDir: string, targetPath: string): boolean {
  const rel = relative(resolve(parentDir), resolve(targetPath));
  return rel.length === 0 || (!rel.startsWith("..") && !isAbsolute(rel));
}

function pushUnique(values: string[], value: string | null): void {
  if (value !== null && !values.includes(value)) {
    values.push(value);
  }
}

function writeFileAtomic(path: string, content: string): void {
  mkdirSync(dirname(path), { recursive: true });
  const tempPath = `${path}.tmp-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  writeFileSync(tempPath, content, "utf8");
  renameSync(tempPath, path);
}

function usageTotal(usage: { input: number; output: number; cacheRead: number; cacheWrite: number; total?: number; totalTokens?: number }): number {
  if (typeof usage.totalTokens === "number") {
    return usage.totalTokens;
  }
  if (typeof usage.total === "number") {
    return usage.total;
  }
  return usage.input + usage.output + usage.cacheRead + usage.cacheWrite;
}

function addUsageTotals(target: AftkPiUsageTotals, usage: { input: number; output: number; cacheRead: number; cacheWrite: number; total?: number; totalTokens?: number }): void {
  target.input += usage.input;
  target.output += usage.output;
  target.cacheRead += usage.cacheRead;
  target.cacheWrite += usage.cacheWrite;
  target.total += usageTotal(usage);
}

function countToolCalls(content: Array<{ type?: string }> | undefined): number {
  if (!Array.isArray(content)) {
    return 0;
  }
  return content.filter((item) => item?.type === "toolCall").length;
}

export function accumulateAgentRun(summary: AftkPiRunCostSummary, messages: AgentEndEvent["messages"]): void {
  summary.runTotals.prompts += 1;

  for (const message of messages) {
    if (message.role === "assistant") {
      const toolCalls = countToolCalls(message.content);
      const modelKey = `${message.provider}/${message.model}`;
      const modelSummary = (summary.byModel[modelKey] ??= {
        assistantMessages: 0,
        toolCalls: 0,
        tokens: createUsageTotals(),
        cost: createUsageTotals(),
      });

      summary.runTotals.assistantMessages += 1;
      summary.runTotals.toolCalls += toolCalls;
      addUsageTotals(summary.runTotals.tokens, message.usage);
      addUsageTotals(summary.runTotals.cost, message.usage.cost);

      modelSummary.assistantMessages += 1;
      modelSummary.toolCalls += toolCalls;
      addUsageTotals(modelSummary.tokens, message.usage);
      addUsageTotals(modelSummary.cost, message.usage.cost);
    }

    if (message.role === "toolResult") {
      summary.runTotals.toolResults += 1;
    }
  }
}

function sessionHeader(ctx: ExtensionContext, timestamp: string): SessionHeader {
  const existing = ctx.sessionManager.getHeader();
  if (existing !== null) {
    return existing;
  }
  return {
    type: "session",
    version: CURRENT_SESSION_VERSION,
    id: ctx.sessionManager.getSessionId(),
    timestamp,
    cwd: ctx.cwd,
  };
}

function serializeSessionSnapshot(header: SessionHeader, entries: SessionEntry[]): string {
  const lines = [header, ...entries].map((entry) => JSON.stringify(entry));
  return lines.join("\n") + "\n";
}

function syncSessionMirror(logFile: string, ctx: ExtensionContext, startedAt: string): void {
  const header = sessionHeader(ctx, startedAt);
  const entries = ctx.sessionManager.getEntries();
  writeFileAtomic(logFile, serializeSessionSnapshot(header, entries));
}

function resolveSessionLogRef(cwd: string, sessionId: string, nativeSessionFile: string | undefined): SessionLogRef {
  const resolvedNative = nativeSessionFile === undefined ? undefined : isAbsolute(nativeSessionFile) ? nativeSessionFile : resolve(cwd, nativeSessionFile);
  if (resolvedNative !== undefined && isInsideDir(resolveLogsDir(cwd), resolvedNative)) {
    return {
      sessionId,
      nativeSessionFile: resolvedNative,
      logFile: resolvedNative,
      logMode: "native",
    };
  }
  return {
    sessionId,
    nativeSessionFile: resolvedNative,
    logFile: resolveMirroredSessionLogFile(cwd, sessionId),
    logMode: "mirror",
  };
}

function createRunSummary(ctx: ExtensionContext, runId: string, startedAt: string): AftkPiRunCostSummary {
  const sessionId = ctx.sessionManager.getSessionId();
  const logRef = resolveSessionLogRef(ctx.cwd, sessionId, ctx.sessionManager.getSessionFile());
  const sessionFile = projectPath(ctx.cwd, logRef.logFile);
  const nativeSessionFile = projectPath(ctx.cwd, logRef.nativeSessionFile);

  return {
    schemaVersion: SUMMARY_SCHEMA_VERSION,
    runId,
    cwd: ctx.cwd.replace(/\\/g, "/"),
    startedAt,
    updatedAt: startedAt,
    sessionId,
    sessionIds: [sessionId],
    sessionFile: sessionFile ?? projectPath(ctx.cwd, logRef.logFile) ?? logRef.logFile.replace(/\\/g, "/"),
    sessionFiles: sessionFile === null ? [] : [sessionFile],
    nativeSessionFile,
    nativeSessionFiles: nativeSessionFile === null ? [] : [nativeSessionFile],
    logMode: logRef.logMode,
    persisted: logRef.nativeSessionFile !== undefined,
    runTotals: createRunTotals(),
    byModel: {},
  };
}

function ensureRunState(current: MutableRunState | undefined, ctx: ExtensionContext, options: AftkPiLoggingOptions): MutableRunState {
  if (current !== undefined) {
    return current;
  }

  const now = options.now?.() ?? new Date();
  const runId = createRunId(now, options.pid, options.randomSuffix?.());
  const startedAt = now.toISOString();
  const summary = createRunSummary(ctx, runId, startedAt);

  return {
    summary,
    costFile: resolveRunCostFile(ctx.cwd, runId),
  };
}

function syncSessionReference(state: MutableRunState, ctx: ExtensionContext): SessionLogRef {
  const logRef = resolveSessionLogRef(ctx.cwd, ctx.sessionManager.getSessionId(), ctx.sessionManager.getSessionFile());
  state.summary.sessionId = logRef.sessionId;
  state.summary.sessionFile = projectPath(ctx.cwd, logRef.logFile) ?? logRef.logFile.replace(/\\/g, "/");
  state.summary.nativeSessionFile = projectPath(ctx.cwd, logRef.nativeSessionFile);
  state.summary.logMode = logRef.logMode;
  state.summary.persisted = state.summary.persisted || logRef.nativeSessionFile !== undefined;
  pushUnique(state.summary.sessionIds, logRef.sessionId);
  pushUnique(state.summary.sessionFiles, state.summary.sessionFile);
  pushUnique(state.summary.nativeSessionFiles, state.summary.nativeSessionFile);
  return logRef;
}

function flushSummary(state: MutableRunState, timestamp: string, ended: boolean): void {
  state.summary.updatedAt = timestamp;
  if (ended) {
    state.summary.endedAt = timestamp;
  }
  writeFileAtomic(state.costFile, JSON.stringify(state.summary, null, 2) + "\n");
}

function syncSessionArtifacts(state: MutableRunState, ctx: ExtensionContext, timestamp: string, ended: boolean): void {
  const logRef = syncSessionReference(state, ctx);
  mkdirSync(resolveLogsDir(ctx.cwd), { recursive: true });
  mkdirSync(resolveCostDir(ctx.cwd), { recursive: true });
  if (logRef.logMode === "mirror") {
    syncSessionMirror(logRef.logFile, ctx, state.summary.startedAt);
  }
  flushSummary(state, timestamp, ended);
}

export function registerAftkLoggingExtension(pi: AftkPiLoggingExtensionAPI, options: AftkPiLoggingOptions = {}): AftkPiLoggingController {
  let state: MutableRunState | undefined;

  const timestamp = (): string => (options.now?.() ?? new Date()).toISOString();

  pi.on("session_directory", (event) => {
    const sessionDir = resolveLogsDir(event.cwd);
    mkdirSync(sessionDir, { recursive: true });
    return { sessionDir };
  });

  pi.on("session_start", async (_event, ctx) => {
    state = ensureRunState(state, ctx, options);
    syncSessionArtifacts(state, ctx, timestamp(), false);
  });

  pi.on("session_switch", async (_event, ctx) => {
    state = ensureRunState(state, ctx, options);
    syncSessionArtifacts(state, ctx, timestamp(), false);
  });

  pi.on("session_fork", async (_event, ctx) => {
    state = ensureRunState(state, ctx, options);
    syncSessionArtifacts(state, ctx, timestamp(), false);
  });

  pi.on("agent_end", async (event, ctx) => {
    state = ensureRunState(state, ctx, options);
    syncSessionReference(state, ctx);
    accumulateAgentRun(state.summary, event.messages);
    syncSessionArtifacts(state, ctx, timestamp(), false);
  });

  pi.on("session_shutdown", async (_event, ctx) => {
    state = ensureRunState(state, ctx, options);
    syncSessionArtifacts(state, ctx, timestamp(), true);
  });

  return {
    getSummary() {
      return state === undefined ? undefined : JSON.parse(JSON.stringify(state.summary));
    },
    flush() {
      if (state !== undefined) {
        flushSummary(state, timestamp(), false);
      }
    },
  };
}
