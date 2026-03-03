import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import * as path from "node:path";
import {
	DEFAULT_MAX_BYTES,
	DEFAULT_MAX_LINES,
	formatSize,
	truncateHead,
	type ExtensionAPI,
} from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";

const HUB_COMMAND = "lake";
const HUB_ARGS = ["exe", "aftk_server"];
const DEFAULT_REQUEST_TIMEOUT_MS = 120_000;
const SHUTDOWN_TIMEOUT_MS = 5_000;

interface OpenResult {
	path: string;
	opened: boolean;
}

interface CloseResult {
	path: string;
	closed: boolean;
}

interface LoadNodeResult {
	id: string[];
}

interface GetGoalsResult {
	goals: string[];
}

interface RunTacticResult {
	goals: string[];
	nextId: string;
}

interface RunTacticStepsResult {
	results: RunTacticResult[];
}

interface SourcePosition {
	line: number;
	col: number;
}

interface SourceRange {
	start: SourcePosition;
	stop: SourcePosition;
}

interface HoverResult {
	text: string;
	range?: SourceRange | null;
}

interface PlainGoalResult {
	goals: string[];
	rendered: string;
}

interface PlainTermGoalResult {
	goal: string;
	range?: SourceRange | null;
}

interface InfoViewResult {
	hover?: HoverResult | null;
	plainGoal?: PlainGoalResult | null;
	plainTermGoal?: PlainTermGoalResult | null;
}

interface ShutdownResult {
	stopped: number;
}

class HubRpcError extends Error {
	readonly method: string;
	readonly code: number;
	readonly data: unknown;

	constructor(method: string, code: number, message: string, data?: unknown) {
		super(message);
		this.name = "HubRpcError";
		this.method = method;
		this.code = code;
		this.data = data;
	}
}

type PendingRequest = {
	method: string;
	resolve: (value: unknown) => void;
	reject: (error: Error) => void;
	timeout: ReturnType<typeof setTimeout>;
};

class AftkHubClient {
	private child: ReturnType<typeof spawn> | null = null;
	private startPromise: Promise<void> | null = null;
	private stdoutBuffer = "";
	private nextId = 1;
	private pending = new Map<string, PendingRequest>();

	constructor(private readonly projectRoot: string) {}

	private isChildRunning(child = this.child): child is NonNullable<typeof this.child> {
		return !!child && child.exitCode === null && !child.killed;
	}

	private processLabel(): string {
		return `${HUB_COMMAND} ${HUB_ARGS.join(" ")} (cwd: ${this.projectRoot})`;
	}

	private async ensureStarted(): Promise<void> {
		if (this.isChildRunning()) return;
		if (this.startPromise) return this.startPromise;

		this.startPromise = new Promise<void>((resolve, reject) => {
			let didSpawn = false;
			let startRejected = false;

			const child = spawn(HUB_COMMAND, HUB_ARGS, {
				cwd: this.projectRoot,
				stdio: ["pipe", "pipe", "pipe"],
				env: process.env,
			});

			if (!child.stdin || !child.stdout || !child.stderr) {
				reject(new Error(`Failed to start ${this.processLabel()}: missing stdio pipes`));
				return;
			}

			this.child = child;
			this.stdoutBuffer = "";

			child.stdout.setEncoding("utf8");
			child.stdout.on("data", (chunk: string) => this.onStdoutChunk(chunk));
			child.stderr.on("data", (chunk: Buffer | string) => {
				process.stderr.write(chunk);
			});

			child.once("spawn", () => {
				didSpawn = true;
				resolve();
			});

			child.on("error", (error) => {
				const wrapped = new Error(`AFTK hub process error: ${error.message}`);
				if (!didSpawn && !startRejected) {
					startRejected = true;
					reject(wrapped);
					return;
				}
				this.rejectAllPending(wrapped);
			});

			child.on("exit", (code, signal) => {
				const details = `AFTK hub exited (code=${code ?? "null"}, signal=${signal ?? "none"})`;
				if (this.child === child) {
					this.child = null;
				}
				this.stdoutBuffer = "";
				this.rejectAllPending(new Error(details));
				if (!didSpawn && !startRejected) {
					startRejected = true;
					reject(new Error(`Failed to start ${this.processLabel()}: ${details}`));
				}
			});
		}).finally(() => {
			this.startPromise = null;
		});

		return this.startPromise;
	}

	private onStdoutChunk(chunk: string): void {
		this.stdoutBuffer += chunk;

		while (true) {
			const newlineIndex = this.stdoutBuffer.indexOf("\n");
			if (newlineIndex < 0) return;

			const line = this.stdoutBuffer.slice(0, newlineIndex).trim();
			this.stdoutBuffer = this.stdoutBuffer.slice(newlineIndex + 1);
			if (!line) continue;

			this.onResponseLine(line);
		}
	}

	private onResponseLine(line: string): void {
		let message: any;
		try {
			message = JSON.parse(line);
		} catch {
			return;
		}

		if (!message || typeof message !== "object" || !("id" in message)) {
			return;
		}

		const idKey = String(message.id);
		const pending = this.pending.get(idKey);
		if (!pending) return;

		this.pending.delete(idKey);
		clearTimeout(pending.timeout);

		if (message.error && typeof message.error === "object") {
			const code = typeof message.error.code === "number" ? message.error.code : -32603;
			const msg = typeof message.error.message === "string" ? message.error.message : "Unknown JSON-RPC error";
			pending.reject(new HubRpcError(pending.method, code, msg, message.error.data));
			return;
		}

		pending.resolve(message.result);
	}

	private rejectAllPending(error: Error): void {
		for (const pending of this.pending.values()) {
			clearTimeout(pending.timeout);
			pending.reject(error);
		}
		this.pending.clear();
	}

	async request<T>(
		method: string,
		params: unknown,
		options?: { timeoutMs?: number; autoStart?: boolean },
	): Promise<T> {
		const timeoutMs = options?.timeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS;
		const autoStart = options?.autoStart ?? true;

		if (autoStart) {
			await this.ensureStarted();
		}

		const child = this.child;
		if (!this.isChildRunning(child) || !child.stdin?.writable) {
			throw new Error(`AFTK hub is not running (${this.processLabel()})`);
		}

		const id = this.nextId++;
		const idKey = String(id);
		const payload =
			JSON.stringify({
				jsonrpc: "2.0",
				id,
				method,
				params,
			}) + "\n";

		return await new Promise<T>((resolve, reject) => {
			const timeout = setTimeout(() => {
				this.pending.delete(idKey);
				reject(new Error(`AFTK hub request timed out after ${Math.round(timeoutMs / 1000)}s: ${method}`));
			}, timeoutMs);

			this.pending.set(idKey, {
				method,
				resolve: (value) => resolve(value as T),
				reject,
				timeout,
			});

			child.stdin.write(payload, "utf8", (error) => {
				if (!error) return;
				const pending = this.pending.get(idKey);
				if (!pending) return;
				this.pending.delete(idKey);
				clearTimeout(timeout);
				reject(new Error(`Failed to send '${method}' request to AFTK hub: ${error.message}`));
			});
		});
	}

	async stop(graceful: boolean): Promise<void> {
		const child = this.child;
		if (!child) return;

		if (graceful && this.isChildRunning(child)) {
			try {
				await this.request<ShutdownResult>("shutdown", {}, { timeoutMs: SHUTDOWN_TIMEOUT_MS, autoStart: false });
			} catch {
				// Fall through to termination.
			}
		}

		await this.terminateChild(child);
	}

	private async terminateChild(child: NonNullable<typeof this.child>): Promise<void> {
		if (child.exitCode !== null || child.killed) {
			if (this.child === child) this.child = null;
			return;
		}

		child.kill("SIGTERM");
		const exitedAfterTerm = await this.waitForExit(child, 1_500);
		if (!exitedAfterTerm && child.exitCode === null && !child.killed) {
			child.kill("SIGKILL");
			await this.waitForExit(child, 1_500);
		}

		if (this.child === child) {
			this.child = null;
		}
	}

	private waitForExit(child: NonNullable<typeof this.child>, timeoutMs: number): Promise<boolean> {
		return new Promise((resolve) => {
			if (child.exitCode !== null || child.killed) {
				resolve(true);
				return;
			}

			const onExit = () => {
				clearTimeout(timer);
				resolve(true);
			};

			const timer = setTimeout(() => {
				child.off("exit", onExit);
				resolve(false);
			}, timeoutMs);

			child.once("exit", onExit);
		});
	}
}

function normalizePath(rawPath: string): string {
	return rawPath.startsWith("@") ? rawPath.slice(1) : rawPath;
}

function findProjectRoot(startDir: string): string {
	let current = path.resolve(startDir);
	while (true) {
		if (existsSync(path.join(current, "lakefile.toml")) || existsSync(path.join(current, "lakefile.lean"))) {
			return current;
		}
		const parent = path.dirname(current);
		if (parent === current) {
			return path.resolve(startDir);
		}
		current = parent;
	}
}

function truncateText(text: string): string {
	const truncation = truncateHead(text, {
		maxBytes: DEFAULT_MAX_BYTES,
		maxLines: DEFAULT_MAX_LINES,
	});

	if (!truncation.truncated) return truncation.content;

	return `${truncation.content}\n\n[Output truncated: showing ${truncation.outputLines} of ${truncation.totalLines} lines (${formatSize(truncation.outputBytes)} of ${formatSize(truncation.totalBytes)})]`;
}

function formatForContent(value: unknown): string {
	if (typeof value === "string") return truncateText(value);
	try {
		return truncateText(JSON.stringify(value, null, 2));
	} catch {
		return truncateText(String(value));
	}
}

function toErrorResult(error: unknown) {
	if (error instanceof HubRpcError) {
		const lines = [`AFTK hub RPC error (${error.method})`, `code: ${error.code}`, `message: ${error.message}`];
		if (error.data !== undefined) {
			lines.push(`data: ${formatForContent(error.data)}`);
		}
		return {
			content: [{ type: "text" as const, text: lines.join("\n") }],
			isError: true,
			details: {
				type: "rpc_error",
				method: error.method,
				code: error.code,
				message: error.message,
				data: error.data,
			},
		};
	}

	const message = error instanceof Error ? error.message : String(error);
	return {
		content: [{ type: "text" as const, text: `AFTK hub tool failed: ${message}` }],
		isError: true,
		details: {
			type: "runtime_error",
			message,
		},
	};
}

async function withAbort<T>(promise: Promise<T>, signal: AbortSignal | undefined, label: string): Promise<T> {
	if (!signal) return promise;
	if (signal.aborted) throw new Error(`Cancelled before ${label}`);

	return await new Promise<T>((resolve, reject) => {
		const onAbort = () => reject(new Error(`Cancelled ${label}`));
		signal.addEventListener("abort", onAbort, { once: true });
		promise.then(
			(value) => {
				signal.removeEventListener("abort", onAbort);
				resolve(value);
			},
			(error) => {
				signal.removeEventListener("abort", onAbort);
				reject(error);
			},
		);
	});
}

const OpenParams = Type.Object({
	path: Type.String({ description: "Path to the Lean source file to open in the hub" }),
});

const CloseParams = Type.Object({
	path: Type.String({ description: "Path to the Lean source file to close" }),
});

const LocationParams = Type.Object({
	path: Type.String({ description: "Path to the Lean source file" }),
	line: Type.Integer({ minimum: 1, description: "1-based line number" }),
	col: Type.Integer({ minimum: 1, description: "1-based column number" }),
});

const LoadNodeParams = LocationParams;
const GetHoverParams = LocationParams;
const GetPlainGoalParams = LocationParams;
const GetPlainTermGoalParams = LocationParams;
const GetInfoViewParams = LocationParams;

const GetGoalsParams = Type.Object({
	path: Type.String({ description: "Path to the Lean source file" }),
	id: Type.String({ description: "Node id to query" }),
});

const RunTacticParams = Type.Object({
	path: Type.String({ description: "Path to the Lean source file" }),
	id: Type.String({ description: "Node id to run tactic from" }),
	tactic: Type.String({ description: "Lean tactic to execute" }),
});

const RunTacticStepsParams = Type.Object({
	path: Type.String({ description: "Path to the Lean source file" }),
	id: Type.String({ description: "Initial node id" }),
	tactics: Type.Array(Type.String({ minLength: 1 }), {
		minItems: 1,
		description: "Ordered list of tactics to run",
	}),
});

const EmptyParams = Type.Object({});

function formatGoals(goals: string[]): string {
	if (goals.length === 0) return "No goals.";
	return goals.map((goal, index) => `${index + 1}. ${goal}`).join("\n\n");
}

function formatRange(range?: SourceRange | null): string {
	if (!range) return "";
	return ` (range: ${range.start.line}:${range.start.col}-${range.stop.line}:${range.stop.col})`;
}

function formatHoverResult(result: HoverResult | null | undefined): string {
	if (!result) return "No hover information at this location.";
	return `${result.text}${formatRange(result.range)}`;
}

function formatPlainGoalResult(result: PlainGoalResult | null | undefined): string {
	if (!result) return "No goal information at this location.";
	if (result.rendered.trim().length === 0) {
		return formatGoals(result.goals);
	}
	return result.rendered;
}

function formatPlainTermGoalResult(result: PlainTermGoalResult | null | undefined): string {
	if (!result) return "No term goal information at this location.";
	return `${result.goal}${formatRange(result.range)}`;
}

function formatInfoViewResult(result: InfoViewResult): string {
	const sections: string[] = [];
	sections.push(`Hover\n-----\n${formatHoverResult(result.hover)}`);
	sections.push(`Goal\n----\n${formatPlainGoalResult(result.plainGoal)}`);
	sections.push(`Term goal\n---------\n${formatPlainTermGoalResult(result.plainTermGoal)}`);
	return sections.join("\n\n");
}

function createHubRequester(client: AftkHubClient) {
	return async function request<T>(
		method: string,
		params: Record<string, unknown>,
		signal: AbortSignal | undefined,
	): Promise<T> {
		return await withAbort(client.request<T>(method, params), signal, method);
	};
}

export default function (pi: ExtensionAPI) {
	const projectRoot = findProjectRoot(process.cwd());
	const client = new AftkHubClient(projectRoot);
	const request = createHubRequester(client);

	pi.on("session_shutdown", async () => {
		await client.stop(true);
	});

	pi.registerCommand("aftk-hub-stop", {
		description: "Stop the local aftk_server process managed by this extension",
		handler: async (_args, ctx) => {
			await client.stop(true);
			if (ctx.hasUI) {
				ctx.ui.notify("AFTK hub stopped", "info");
			}
		},
	});

	pi.registerTool({
		name: "aftk_open",
		label: "AFTK Open",
		description: "Open a Lean file in the AFTK hub server (spawns or reuses its file worker).",
		parameters: OpenParams,
		async execute(_toolCallId, params, signal, _onUpdate, _ctx) {
			try {
				const path = normalizePath(params.path);
				const result = await request<OpenResult>("open", { path }, signal);
				const text = result.opened ? `Opened file worker: ${result.path}` : `File already open: ${result.path}`;
				return {
					content: [{ type: "text", text }],
					details: result,
				};
			} catch (error) {
				return toErrorResult(error);
			}
		},
	});

	pi.registerTool({
		name: "aftk_close",
		label: "AFTK Close",
		description: "Close a Lean file in the AFTK hub server and stop its file worker.",
		parameters: CloseParams,
		async execute(_toolCallId, params, signal, _onUpdate, _ctx) {
			try {
				const path = normalizePath(params.path);
				const result = await request<CloseResult>("close", { path }, signal);
				const text = result.closed ? `Closed file worker: ${result.path}` : `File was not open: ${result.path}`;
				return {
					content: [{ type: "text", text }],
					details: result,
				};
			} catch (error) {
				return toErrorResult(error);
			}
		},
	});

	pi.registerTool({
		name: "aftk_load_node",
		label: "AFTK Load Node",
		description: "Resolve a source location to a tactic node id for an open Lean file.",
		parameters: LoadNodeParams,
		async execute(_toolCallId, params, signal, _onUpdate, _ctx) {
			try {
				const path = normalizePath(params.path);
				const result = await request<LoadNodeResult>("load_node", {
					path,
					line: params.line,
					col: params.col,
				}, signal);
				const renderedId = result.id.length > 0 ? result.id.join(" / ") : "(root)";
				return {
					content: [{ type: "text", text: `Node id: ${renderedId}` }],
					details: result,
				};
			} catch (error) {
				return toErrorResult(error);
			}
		},
	});

	pi.registerTool({
		name: "aftk_get_hover",
		label: "AFTK Get Hover",
		description: "Fetch plain-text hover information at a source location for an open Lean file.",
		parameters: GetHoverParams,
		async execute(_toolCallId, params, signal, _onUpdate, _ctx) {
			try {
				const path = normalizePath(params.path);
				const result = await request<HoverResult | null>("get_hover", {
					path,
					line: params.line,
					col: params.col,
				}, signal);
				return {
					content: [{ type: "text", text: truncateText(formatHoverResult(result)) }],
					details: result,
				};
			} catch (error) {
				return toErrorResult(error);
			}
		},
	});

	pi.registerTool({
		name: "aftk_get_plain_goal",
		label: "AFTK Get Plain Goal",
		description: "Fetch plain infoview goal-state content at a source location for an open Lean file.",
		parameters: GetPlainGoalParams,
		async execute(_toolCallId, params, signal, _onUpdate, _ctx) {
			try {
				const path = normalizePath(params.path);
				const result = await request<PlainGoalResult | null>("get_plain_goal", {
					path,
					line: params.line,
					col: params.col,
				}, signal);
				return {
					content: [{ type: "text", text: truncateText(formatPlainGoalResult(result)) }],
					details: result,
				};
			} catch (error) {
				return toErrorResult(error);
			}
		},
	});

	pi.registerTool({
		name: "aftk_get_plain_term_goal",
		label: "AFTK Get Plain Term Goal",
		description: "Fetch plain expected-type infoview content at a source location for an open Lean file.",
		parameters: GetPlainTermGoalParams,
		async execute(_toolCallId, params, signal, _onUpdate, _ctx) {
			try {
				const path = normalizePath(params.path);
				const result = await request<PlainTermGoalResult | null>("get_plain_term_goal", {
					path,
					line: params.line,
					col: params.col,
				}, signal);
				return {
					content: [{ type: "text", text: truncateText(formatPlainTermGoalResult(result)) }],
					details: result,
				};
			} catch (error) {
				return toErrorResult(error);
			}
		},
	});

	pi.registerTool({
		name: "aftk_get_infoview",
		label: "AFTK Get Infoview",
		description: "Fetch plain hover, goal, and term-goal infoview content at a source location.",
		parameters: GetInfoViewParams,
		async execute(_toolCallId, params, signal, _onUpdate, _ctx) {
			try {
				const path = normalizePath(params.path);
				const result = await request<InfoViewResult>("get_infoview", {
					path,
					line: params.line,
					col: params.col,
				}, signal);
				return {
					content: [{ type: "text", text: truncateText(formatInfoViewResult(result)) }],
					details: result,
				};
			} catch (error) {
				return toErrorResult(error);
			}
		},
	});

	pi.registerTool({
		name: "aftk_get_goals",
		label: "AFTK Get Goals",
		description: "Fetch current goals at a node id for an open Lean file.",
		parameters: GetGoalsParams,
		async execute(_toolCallId, params, signal, _onUpdate, _ctx) {
			try {
				const path = normalizePath(params.path);
				const result = await request<GetGoalsResult>("get_goals", { path, id: params.id }, signal);
				return {
					content: [{ type: "text", text: formatGoals(result.goals) }],
					details: result,
				};
			} catch (error) {
				return toErrorResult(error);
			}
		},
	});

	pi.registerTool({
		name: "aftk_run_tactic",
		label: "AFTK Run Tactic",
		description: "Run one tactic at a node id in an open Lean file.",
		parameters: RunTacticParams,
		async execute(_toolCallId, params, signal, _onUpdate, _ctx) {
			try {
				const path = normalizePath(params.path);
				const result = await request<RunTacticResult>(
					"run_tactic",
					{ path, id: params.id, tactic: params.tactic },
					signal,
				);
				const summary = [`nextId: ${result.nextId}`, "", formatGoals(result.goals)].join("\n");
				return {
					content: [{ type: "text", text: summary }],
					details: result,
				};
			} catch (error) {
				return toErrorResult(error);
			}
		},
	});

	pi.registerTool({
		name: "aftk_run_tactic_steps",
		label: "AFTK Run Tactic Steps",
		description: "Run a sequence of tactics at a node id in an open Lean file.",
		parameters: RunTacticStepsParams,
		async execute(_toolCallId, params, signal, _onUpdate, _ctx) {
			try {
				const path = normalizePath(params.path);
				const result = await request<RunTacticStepsResult>(
					"run_tactic_steps",
					{ path, id: params.id, tactics: params.tactics },
					signal,
				);

				const blocks = result.results.map((step, index) => {
					const header = `Step ${index + 1} nextId: ${step.nextId}`;
					return `${header}\n${"-".repeat(header.length)}\n${formatGoals(step.goals)}`;
				});

				const text = blocks.length > 0 ? blocks.join("\n\n") : "No step results returned.";
				return {
					content: [{ type: "text", text: truncateText(text) }],
					details: result,
				};
			} catch (error) {
				return toErrorResult(error);
			}
		},
	});

	pi.registerTool({
		name: "aftk_shutdown",
		label: "AFTK Shutdown",
		description: "Shutdown the AFTK hub server and stop all managed file workers.",
		parameters: EmptyParams,
		async execute(_toolCallId, _params, signal, _onUpdate, _ctx) {
			try {
				const result = await request<ShutdownResult>("shutdown", {}, signal);
				await client.stop(false);
				return {
					content: [{ type: "text", text: `Stopped ${result.stopped} file worker(s).` }],
					details: result,
				};
			} catch (error) {
				return toErrorResult(error);
			}
		},
	});
}
