import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import {
  createRunId,
  registerAftkLoggingExtension,
  resolveLogsDir,
  resolveMirroredSessionLogFile,
  resolveRunCostFile,
  type AftkPiLoggingExtensionAPI,
} from "../../../src/hosts/pi/index.ts";

function createMockPi() {
  const handlers = new Map<string, Function>();
  const pi = {
    on(event: string, handler: Function) {
      handlers.set(event, handler);
    },
  } as unknown as AftkPiLoggingExtensionAPI;
  return { pi, handlers };
}

function createSessionContext(cwd: string, options: { sessionId: string; sessionFile?: string }) {
  const state = {
    sessionId: options.sessionId,
    sessionFile: options.sessionFile,
    header: null as any,
    entries: [] as any[],
  };

  const ctx = {
    cwd,
    sessionManager: {
      getHeader: () => state.header,
      getEntries: () => state.entries,
      getSessionId: () => state.sessionId,
      getSessionFile: () => state.sessionFile,
    },
  } as any;

  return { state, ctx };
}

test("registerAftkLoggingExtension resolves project-local session and cost paths", async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), "aftk-pi-logging-"));
  try {
    const { pi, handlers } = createMockPi();
    registerAftkLoggingExtension(pi, {
      now: () => new Date("2026-03-13T21:12:11.123Z"),
      pid: 12345,
      randomSuffix: () => "seed",
    });

    const runId = createRunId(new Date("2026-03-13T21:12:11.123Z"), 12345, "seed");
    assert.equal(runId, "run-2026-03-13T21-12-11.123Z-pid12345-seed");
    assert.equal(resolveRunCostFile(tempDir, runId), path.join(tempDir, ".aftk", "cost", `${runId}.json`));
    assert.equal(resolveMirroredSessionLogFile(tempDir, "session:1"), path.join(tempDir, ".aftk", "logs", "mirror-session-session-1.jsonl"));

    const result = await handlers.get("session_directory")?.({ type: "session_directory", cwd: tempDir });
    assert.deepEqual(result, { sessionDir: resolveLogsDir(tempDir) });
    assert.equal(existsSync(resolveLogsDir(tempDir)), true);
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test("registerAftkLoggingExtension mirrors non-persisted sessions and aggregates run cost", async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), "aftk-pi-logging-"));
  try {
    const now = new Date("2026-03-13T21:12:11.123Z");
    const { pi, handlers } = createMockPi();
    registerAftkLoggingExtension(pi, {
      now: () => now,
      pid: 12345,
      randomSuffix: () => "seed",
    });

    const { state, ctx } = createSessionContext(tempDir, { sessionId: "session-1" });
    const runId = createRunId(now, 12345, "seed");
    const costFile = resolveRunCostFile(tempDir, runId);
    const logFile = resolveMirroredSessionLogFile(tempDir, "session-1");

    await handlers.get("session_start")?.({ type: "session_start" }, ctx);
    assert.equal(existsSync(costFile), true);
    assert.equal(existsSync(logFile), true);

    const userMessage = {
      role: "user",
      content: "show me the proof",
      timestamp: 1,
    };
    const assistantMessage = {
      role: "assistant",
      content: [
        { type: "text", text: "Trying a tool" },
        { type: "toolCall", toolCallId: "call-1", toolName: "bash", args: { command: "pwd" } },
      ],
      api: "anthropic",
      provider: "anthropic",
      model: "claude-sonnet-4-5",
      usage: {
        input: 11,
        output: 7,
        cacheRead: 3,
        cacheWrite: 2,
        totalTokens: 23,
        cost: {
          input: 0.11,
          output: 0.07,
          cacheRead: 0.03,
          cacheWrite: 0.02,
          total: 0.23,
        },
      },
      stopReason: "toolUse",
      timestamp: 2,
    };
    const toolResultMessage = {
      role: "toolResult",
      toolCallId: "call-1",
      toolName: "bash",
      content: [{ type: "text", text: "/home/dev/aftk" }],
      details: {},
      isError: false,
      timestamp: 3,
    };

    state.entries = [
      { type: "message", id: "u1", parentId: null, timestamp: "2026-03-13T21:12:12.000Z", message: userMessage },
      { type: "message", id: "a1", parentId: "u1", timestamp: "2026-03-13T21:12:13.000Z", message: assistantMessage },
      { type: "message", id: "t1", parentId: "a1", timestamp: "2026-03-13T21:12:14.000Z", message: toolResultMessage },
    ];

    await handlers.get("agent_end")?.({ type: "agent_end", messages: [userMessage, assistantMessage, toolResultMessage] }, ctx);

    const summary = JSON.parse(readFileSync(costFile, "utf8"));
    assert.equal(summary.sessionFile, ".aftk/logs/mirror-session-session-1.jsonl");
    assert.equal(summary.logMode, "mirror");
    assert.equal(summary.persisted, false);
    assert.equal(summary.runTotals.prompts, 1);
    assert.equal(summary.runTotals.assistantMessages, 1);
    assert.equal(summary.runTotals.toolCalls, 1);
    assert.equal(summary.runTotals.toolResults, 1);
    assert.deepEqual(summary.runTotals.tokens, {
      input: 11,
      output: 7,
      cacheRead: 3,
      cacheWrite: 2,
      total: 23,
    });
    assert.deepEqual(summary.runTotals.cost, {
      input: 0.11,
      output: 0.07,
      cacheRead: 0.03,
      cacheWrite: 0.02,
      total: 0.23,
    });
    assert.equal(summary.byModel["anthropic/claude-sonnet-4-5"].assistantMessages, 1);
    assert.equal(summary.byModel["anthropic/claude-sonnet-4-5"].toolCalls, 1);

    const logLines = readFileSync(logFile, "utf8").trim().split("\n");
    assert.equal(logLines.length, 4);
    assert.equal(JSON.parse(logLines[0]!).type, "session");
    assert.equal(JSON.parse(logLines[1]!).message.role, "user");
    assert.equal(JSON.parse(logLines[2]!).message.role, "assistant");
    assert.equal(JSON.parse(logLines[3]!).message.role, "toolResult");

    await handlers.get("session_shutdown")?.({ type: "session_shutdown" }, ctx);
    const shutdownSummary = JSON.parse(readFileSync(costFile, "utf8"));
    assert.equal(shutdownSummary.endedAt, now.toISOString());
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test("registerAftkLoggingExtension reuses native session files already under .aftk/logs", async () => {
  const tempDir = mkdtempSync(path.join(tmpdir(), "aftk-pi-logging-"));
  try {
    const { pi, handlers } = createMockPi();
    registerAftkLoggingExtension(pi, {
      now: () => new Date("2026-03-13T21:12:11.123Z"),
      pid: 12345,
      randomSuffix: () => "seed",
    });

    const nativeSessionFile = path.join(resolveLogsDir(tempDir), "native-session.jsonl");
    const { ctx } = createSessionContext(tempDir, {
      sessionId: "session-native",
      sessionFile: nativeSessionFile,
    });

    await handlers.get("session_start")?.({ type: "session_start" }, ctx);

    const runId = createRunId(new Date("2026-03-13T21:12:11.123Z"), 12345, "seed");
    const summary = JSON.parse(readFileSync(resolveRunCostFile(tempDir, runId), "utf8"));
    assert.equal(summary.sessionFile, ".aftk/logs/native-session.jsonl");
    assert.equal(summary.nativeSessionFile, ".aftk/logs/native-session.jsonl");
    assert.equal(summary.logMode, "native");
    assert.equal(summary.persisted, true);
    assert.equal(existsSync(resolveMirroredSessionLogFile(tempDir, "session-native")), false);
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});
