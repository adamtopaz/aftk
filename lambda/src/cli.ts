#!/usr/bin/env bun

import type { ThinkingLevel } from "@mariozechner/pi-agent-core";
import {
	AuthStorage,
	createAgentSession,
	createBashTool,
	createCodingTools,
	createEditTool,
	createFindTool,
	createGrepTool,
	createLsTool,
	createReadTool,
	createWriteTool,
	DefaultResourceLoader,
	InteractiveMode,
	ModelRegistry,
	runPrintMode,
	runRpcMode,
	SessionManager,
	SettingsManager,
	VERSION,
} from "@mariozechner/pi-coding-agent";
import { createAFTKTools } from "./aftk-tools";

process.title = "lambda";

type LambdaMode = "interactive" | "text" | "json" | "rpc";

interface CliOptions {
	help: boolean;
	version: boolean;
	mode: LambdaMode;
	cwd: string;
	agentDir?: string;
	provider?: string;
	model?: string;
	thinking?: ThinkingLevel;
	continueRecent: boolean;
	session?: string;
	sessionDir?: string;
	noSession: boolean;
	noTools: boolean;
	tools?: string[];
	messages: string[];
}

const VALID_THINKING_LEVELS: ThinkingLevel[] = ["off", "minimal", "low", "medium", "high", "xhigh"];
const SUPPORTED_BUILTIN_TOOL_NAMES = ["read", "bash", "edit", "write", "grep", "find", "ls"] as const;

function printHelp(): void {
	console.log(`lambda - Lean-focused coding agent (pi SDK + AFTK built-ins)

Usage:
  lambda [options] [messages...]

Modes:
  (default)              Interactive mode (same TUI runtime used by pi)
  -p, --print            Print mode (single-shot)
  --mode json            Print mode with JSON event output
  --mode rpc             RPC mode

Model options:
  --provider <name>      Provider name (e.g. anthropic, openai)
  --model <id>           Model id, optionally provider-prefixed (provider/model)
  --thinking <level>     off|minimal|low|medium|high|xhigh

Session options:
  -c, --continue         Continue most recent session
  --session <path>       Open a specific session file
  --session-dir <dir>    Custom session directory
  --no-session           In-memory session only

Tool options:
  --no-tools             Disable built-in coding tools
  --tools <list>         Comma list of built-in tools (${SUPPORTED_BUILTIN_TOOL_NAMES.join(",")})

Other:
  --cwd <dir>            Working directory (default: current directory)
  --agent-dir <dir>      Agent config dir (default: ~/.pi/agent)
  -h, --help             Show this help
  -v, --version          Show version
`);
}

function parseThinkingLevel(raw: string): ThinkingLevel {
	if (!VALID_THINKING_LEVELS.includes(raw as ThinkingLevel)) {
		throw new Error(`Invalid thinking level '${raw}'. Expected one of: ${VALID_THINKING_LEVELS.join(", ")}`);
	}
	return raw as ThinkingLevel;
}

function parseMode(raw: string): LambdaMode {
	if (raw === "json") return "json";
	if (raw === "rpc") return "rpc";
	if (raw === "text") return "text";
	throw new Error(`Invalid mode '${raw}'. Expected one of: text, json, rpc`);
}

function parseArgs(argv: string[]): CliOptions {
	const options: CliOptions = {
		help: false,
		version: false,
		mode: "interactive",
		cwd: process.cwd(),
		continueRecent: false,
		noSession: false,
		noTools: false,
		messages: [],
	};

	for (let i = 0; i < argv.length; i++) {
		const arg = argv[i];

		if (arg === "--") {
			options.messages.push(...argv.slice(i + 1));
			break;
		}

		if (!arg.startsWith("-")) {
			options.messages.push(arg);
			continue;
		}

		switch (arg) {
			case "-h":
			case "--help":
				options.help = true;
				break;
			case "-v":
			case "--version":
				options.version = true;
				break;
			case "-p":
			case "--print":
				options.mode = "text";
				break;
			case "--mode": {
				const value = argv[++i];
				if (!value) throw new Error("Missing value for --mode");
				options.mode = parseMode(value);
				break;
			}
			case "--provider": {
				const value = argv[++i];
				if (!value) throw new Error("Missing value for --provider");
				options.provider = value;
				break;
			}
			case "--model": {
				const value = argv[++i];
				if (!value) throw new Error("Missing value for --model");
				options.model = value;
				break;
			}
			case "--thinking": {
				const value = argv[++i];
				if (!value) throw new Error("Missing value for --thinking");
				options.thinking = parseThinkingLevel(value);
				break;
			}
			case "-c":
			case "--continue":
				options.continueRecent = true;
				break;
			case "--session": {
				const value = argv[++i];
				if (!value) throw new Error("Missing value for --session");
				options.session = value;
				break;
			}
			case "--session-dir": {
				const value = argv[++i];
				if (!value) throw new Error("Missing value for --session-dir");
				options.sessionDir = value;
				break;
			}
			case "--no-session":
				options.noSession = true;
				break;
			case "--no-tools":
				options.noTools = true;
				break;
			case "--tools": {
				const value = argv[++i];
				if (!value) throw new Error("Missing value for --tools");
				options.tools = value
					.split(",")
					.map((item) => item.trim())
					.filter((item) => item.length > 0);
				break;
			}
			case "--cwd": {
				const value = argv[++i];
				if (!value) throw new Error("Missing value for --cwd");
				options.cwd = value;
				break;
			}
			case "--agent-dir": {
				const value = argv[++i];
				if (!value) throw new Error("Missing value for --agent-dir");
				options.agentDir = value;
				break;
			}
			default:
				throw new Error(`Unknown option '${arg}'. Use --help for usage.`);
		}
	}

	if (options.session && options.continueRecent) {
		throw new Error("Cannot combine --session and --continue");
	}

	if (options.noSession && (options.session || options.continueRecent)) {
		throw new Error("Cannot combine --no-session with --session/--continue");
	}

	return options;
}

async function readPipedStdin(): Promise<string | undefined> {
	if (process.stdin.isTTY) return undefined;

	return await new Promise<string | undefined>((resolve) => {
		let data = "";
		process.stdin.setEncoding("utf8");
		process.stdin.on("data", (chunk) => {
			data += chunk;
		});
		process.stdin.on("end", () => {
			const trimmed = data.trim();
			resolve(trimmed.length > 0 ? trimmed : undefined);
		});
		process.stdin.resume();
	});
}

function resolveSessionManager(options: CliOptions): SessionManager {
	if (options.noSession) return SessionManager.inMemory(options.cwd);
	if (options.session) return SessionManager.open(options.session, options.sessionDir);
	if (options.continueRecent) return SessionManager.continueRecent(options.cwd, options.sessionDir);
	return SessionManager.create(options.cwd, options.sessionDir);
}

function resolveBuiltInTools(options: CliOptions) {
	if (options.noTools) return [];

	if (!options.tools || options.tools.length === 0) {
		return createCodingTools(options.cwd);
	}

	const selected = [];
	for (const toolName of options.tools) {
		switch (toolName) {
			case "read":
				selected.push(createReadTool(options.cwd));
				break;
			case "bash":
				selected.push(createBashTool(options.cwd));
				break;
			case "edit":
				selected.push(createEditTool(options.cwd));
				break;
			case "write":
				selected.push(createWriteTool(options.cwd));
				break;
			case "grep":
				selected.push(createGrepTool(options.cwd));
				break;
			case "find":
				selected.push(createFindTool(options.cwd));
				break;
			case "ls":
				selected.push(createLsTool(options.cwd));
				break;
			default:
				throw new Error(
					`Unknown built-in tool '${toolName}'. Available: ${SUPPORTED_BUILTIN_TOOL_NAMES.join(", ")}`,
				);
		}
	}

	return selected;
}

function resolveModelSelection(options: CliOptions, modelRegistry: ModelRegistry): {
	provider?: string;
	modelId?: string;
	thinking?: ThinkingLevel;
} {
	if (!options.model && !options.provider) {
		return {};
	}

	if (!options.model && options.provider) {
		throw new Error("--provider requires --model (or use provider/model format in --model)");
	}

	let provider = options.provider;
	let modelSpec = options.model!;
	let thinking = options.thinking;

	const slashIndex = modelSpec.indexOf("/");
	if (slashIndex >= 0) {
		provider = modelSpec.slice(0, slashIndex);
		modelSpec = modelSpec.slice(slashIndex + 1);
	}

	const colonIndex = modelSpec.lastIndexOf(":");
	if (colonIndex > 0) {
		const maybeThinking = modelSpec.slice(colonIndex + 1);
		if (VALID_THINKING_LEVELS.includes(maybeThinking as ThinkingLevel)) {
			modelSpec = modelSpec.slice(0, colonIndex);
			if (!thinking) {
				thinking = maybeThinking as ThinkingLevel;
			}
		}
	}

	if (!provider) {
		throw new Error("Unable to resolve provider. Use --provider <name> or --model <provider/model>");
	}

	const model = modelRegistry.find(provider, modelSpec);
	if (!model) {
		throw new Error(`Model not found: ${provider}/${modelSpec}`);
	}

	return {
		provider,
		modelId: model.id,
		thinking,
	};
}

async function run(): Promise<void> {
	const options = parseArgs(process.argv.slice(2));

	if (options.help) {
		printHelp();
		return;
	}

	if (options.version) {
		console.log(VERSION);
		return;
	}

	const pipedInput = options.mode === "rpc" ? undefined : await readPipedStdin();
	if (pipedInput) {
		if (options.messages.length > 0) {
			options.messages[0] = `${pipedInput}\n\n${options.messages[0]}`;
		} else {
			options.messages.push(pipedInput);
		}
	}

	const initialMessage = options.messages.length > 0 ? options.messages[0] : undefined;
	const followUpMessages = options.messages.length > 1 ? options.messages.slice(1) : [];

	const settingsManager = SettingsManager.create(options.cwd, options.agentDir);
	const authStorage = AuthStorage.create();
	const modelRegistry = new ModelRegistry(authStorage);
	const sessionManager = resolveSessionManager(options);
	const builtInTools = resolveBuiltInTools(options);
	const modelSelection = resolveModelSelection(options, modelRegistry);

	const resourceLoader = new DefaultResourceLoader({
		cwd: options.cwd,
		agentDir: options.agentDir,
		settingsManager,
		noExtensions: true,
	});
	await resourceLoader.reload();

	const aftkToolset = createAFTKTools({ cwd: options.cwd });

	const resolvedModel =
		modelSelection.provider && modelSelection.modelId
			? modelRegistry.find(modelSelection.provider, modelSelection.modelId)
			: undefined;

	const { session } = await createAgentSession({
		cwd: options.cwd,
		agentDir: options.agentDir,
		authStorage,
		modelRegistry,
		resourceLoader,
		sessionManager,
		settingsManager,
		model: resolvedModel,
		thinkingLevel: modelSelection.thinking,
		tools: builtInTools,
		customTools: aftkToolset.tools,
	});

	try {
		if (options.mode === "rpc") {
			await runRpcMode(session);
			return;
		}

		if (options.mode === "text" || options.mode === "json") {
			await runPrintMode(session, {
				mode: options.mode,
				initialMessage,
				messages: followUpMessages,
			});
			return;
		}

		const interactive = new InteractiveMode(session, {
			initialMessage,
			initialMessages: followUpMessages,
		});
		await interactive.run();
	} finally {
		await aftkToolset.shutdown(true);
	}
}

run().catch((error) => {
	const message = error instanceof Error ? error.message : String(error);
	console.error(`lambda error: ${message}`);
	process.exitCode = 1;
});
