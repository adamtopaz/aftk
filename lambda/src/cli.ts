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

type RegistryModel = ReturnType<ModelRegistry["getAll"]>[number];

// Keep this map aligned with pi-coding-agent's core/model-resolver defaults.
const DEFAULT_MODEL_PER_PROVIDER: Record<string, string> = {
	"amazon-bedrock": "us.anthropic.claude-opus-4-6-v1",
	anthropic: "claude-opus-4-6",
	openai: "gpt-5.1-codex",
	"azure-openai-responses": "gpt-5.2",
	"openai-codex": "gpt-5.3-codex",
	google: "gemini-2.5-pro",
	"google-gemini-cli": "gemini-2.5-pro",
	"google-antigravity": "gemini-3.1-pro-high",
	"google-vertex": "gemini-3-pro-preview",
	"github-copilot": "gpt-4o",
	openrouter: "openai/gpt-5.1-codex",
	"vercel-ai-gateway": "anthropic/claude-opus-4-6",
	xai: "grok-4-fast-non-reasoning",
	groq: "openai/gpt-oss-120b",
	cerebras: "zai-glm-4.6",
	zai: "glm-4.6",
	mistral: "devstral-medium-latest",
	minimax: "MiniMax-M2.1",
	"minimax-cn": "MiniMax-M2.1",
	huggingface: "moonshotai/Kimi-K2.5",
	opencode: "claude-opus-4-6",
	"opencode-go": "kimi-k2.5",
	"kimi-coding": "kimi-k2-thinking",
};

function isAlias(modelId: string): boolean {
	if (modelId.endsWith("-latest")) return true;
	const dateSuffix = /-\d{8}$/;
	return !dateSuffix.test(modelId);
}

function tryMatchModel(modelPattern: string, availableModels: RegistryModel[]): RegistryModel | undefined {
	const slashIndex = modelPattern.indexOf("/");
	if (slashIndex !== -1) {
		const provider = modelPattern.substring(0, slashIndex);
		const modelId = modelPattern.substring(slashIndex + 1);
		const providerMatch = availableModels.find(
			(model) =>
				model.provider.toLowerCase() === provider.toLowerCase() && model.id.toLowerCase() === modelId.toLowerCase(),
		);
		if (providerMatch) return providerMatch;
	}

	const exactMatch = availableModels.find((model) => model.id.toLowerCase() === modelPattern.toLowerCase());
	if (exactMatch) return exactMatch;

	const matches = availableModels.filter(
		(model) =>
			model.id.toLowerCase().includes(modelPattern.toLowerCase()) ||
			model.name?.toLowerCase().includes(modelPattern.toLowerCase()),
	);
	if (matches.length === 0) return undefined;

	const aliases = matches.filter((model) => isAlias(model.id));
	const datedVersions = matches.filter((model) => !isAlias(model.id));

	if (aliases.length > 0) {
		aliases.sort((a, b) => b.id.localeCompare(a.id));
		return aliases[0];
	}

	datedVersions.sort((a, b) => b.id.localeCompare(a.id));
	return datedVersions[0];
}

function parseModelPattern(
	pattern: string,
	availableModels: RegistryModel[],
	options?: { allowInvalidThinkingLevelFallback?: boolean },
): {
	model: RegistryModel | undefined;
	thinkingLevel?: ThinkingLevel;
	warning?: string;
} {
	const exactMatch = tryMatchModel(pattern, availableModels);
	if (exactMatch) {
		return { model: exactMatch, thinkingLevel: undefined, warning: undefined };
	}

	const lastColonIndex = pattern.lastIndexOf(":");
	if (lastColonIndex === -1) {
		return { model: undefined, thinkingLevel: undefined, warning: undefined };
	}

	const prefix = pattern.substring(0, lastColonIndex);
	const suffix = pattern.substring(lastColonIndex + 1);

	if (VALID_THINKING_LEVELS.includes(suffix as ThinkingLevel)) {
		const result = parseModelPattern(prefix, availableModels, options);
		if (result.model) {
			return {
				model: result.model,
				thinkingLevel: result.warning ? undefined : (suffix as ThinkingLevel),
				warning: result.warning,
			};
		}
		return result;
	}

	const allowFallback = options?.allowInvalidThinkingLevelFallback ?? true;
	if (!allowFallback) {
		return { model: undefined, thinkingLevel: undefined, warning: undefined };
	}

	const result = parseModelPattern(prefix, availableModels, options);
	if (result.model) {
		return {
			model: result.model,
			thinkingLevel: undefined,
			warning: `Invalid thinking level "${suffix}" in pattern "${pattern}". Using default instead.`,
		};
	}

	return result;
}

function buildFallbackModel(
	provider: string,
	modelId: string,
	availableModels: RegistryModel[],
): RegistryModel | undefined {
	const providerModels = availableModels.filter((model) => model.provider === provider);
	if (providerModels.length === 0) return undefined;

	const defaultId = DEFAULT_MODEL_PER_PROVIDER[provider];
	const baseModel = defaultId
		? (providerModels.find((model) => model.id === defaultId) ?? providerModels[0])
		: providerModels[0];

	return {
		...baseModel,
		id: modelId,
		name: modelId,
	} as RegistryModel;
}

function resolveCliModelLikePi(options: {
	cliProvider?: string;
	cliModel?: string;
	modelRegistry: ModelRegistry;
}): {
	model: RegistryModel | undefined;
	thinkingLevel?: ThinkingLevel;
	warning?: string;
	error?: string;
} {
	const { cliProvider, cliModel, modelRegistry } = options;

	if (!cliModel) {
		return { model: undefined, warning: undefined, error: undefined };
	}

	const availableModels = modelRegistry.getAll();
	if (availableModels.length === 0) {
		return {
			model: undefined,
			warning: undefined,
			error: "No models available. Check your installation or add models to models.json.",
		};
	}

	const providerMap = new Map<string, string>();
	for (const model of availableModels) {
		providerMap.set(model.provider.toLowerCase(), model.provider);
	}

	let provider = cliProvider ? providerMap.get(cliProvider.toLowerCase()) : undefined;
	if (cliProvider && !provider) {
		return {
			model: undefined,
			warning: undefined,
			error: `Unknown provider "${cliProvider}".`,
		};
	}

	let pattern = cliModel;
	let inferredProvider = false;

	if (!provider) {
		const slashIndex = cliModel.indexOf("/");
		if (slashIndex !== -1) {
			const maybeProvider = cliModel.substring(0, slashIndex);
			const canonical = providerMap.get(maybeProvider.toLowerCase());
			if (canonical) {
				provider = canonical;
				pattern = cliModel.substring(slashIndex + 1);
				inferredProvider = true;
			}
		}
	}

	if (!provider) {
		const lower = cliModel.toLowerCase();
		const exact = availableModels.find(
			(model) => model.id.toLowerCase() === lower || `${model.provider}/${model.id}`.toLowerCase() === lower,
		);
		if (exact) {
			return { model: exact, warning: undefined, thinkingLevel: undefined, error: undefined };
		}
	}

	if (cliProvider && provider) {
		const prefix = `${provider}/`;
		if (cliModel.toLowerCase().startsWith(prefix.toLowerCase())) {
			pattern = cliModel.substring(prefix.length);
		}
	}

	const candidates = provider
		? availableModels.filter((model) => model.provider === provider)
		: availableModels;
	const { model, thinkingLevel, warning } = parseModelPattern(pattern, candidates, {
		allowInvalidThinkingLevelFallback: false,
	});
	if (model) {
		return { model, thinkingLevel, warning, error: undefined };
	}

	if (inferredProvider) {
		const lower = cliModel.toLowerCase();
		const exact = availableModels.find(
			(candidate) =>
				candidate.id.toLowerCase() === lower || `${candidate.provider}/${candidate.id}`.toLowerCase() === lower,
		);
		if (exact) {
			return { model: exact, warning: undefined, thinkingLevel: undefined, error: undefined };
		}

		const fallback = parseModelPattern(cliModel, availableModels, {
			allowInvalidThinkingLevelFallback: false,
		});
		if (fallback.model) {
			return {
				model: fallback.model,
				thinkingLevel: fallback.thinkingLevel,
				warning: fallback.warning,
				error: undefined,
			};
		}
	}

	if (provider) {
		const fallbackModel = buildFallbackModel(provider, pattern, availableModels);
		if (fallbackModel) {
			const fallbackWarning = warning
				? `${warning} Model "${pattern}" not found for provider "${provider}". Using custom model id.`
				: `Model "${pattern}" not found for provider "${provider}". Using custom model id.`;
			return {
				model: fallbackModel,
				thinkingLevel: undefined,
				warning: fallbackWarning,
				error: undefined,
			};
		}
	}

	const display = provider ? `${provider}/${pattern}` : cliModel;
	return {
		model: undefined,
		thinkingLevel: undefined,
		warning,
		error: `Model "${display}" not found.`,
	};
}

function resolveModelSelection(options: CliOptions, modelRegistry: ModelRegistry): {
	model?: RegistryModel;
	thinking?: ThinkingLevel;
} {
	if (!options.model && !options.provider) {
		return {};
	}

	if (!options.model && options.provider) {
		throw new Error("--provider requires --model (or use provider/model format in --model)");
	}

	const resolved = resolveCliModelLikePi({
		cliProvider: options.provider,
		cliModel: options.model,
		modelRegistry,
	});

	if (resolved.warning) {
		console.warn(`lambda warning: ${resolved.warning}`);
	}

	if (resolved.error || !resolved.model) {
		throw new Error(resolved.error ?? `Model not found: ${options.model}`);
	}

	return {
		model: resolved.model,
		thinking: options.thinking ?? resolved.thinkingLevel,
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

	const { session } = await createAgentSession({
		cwd: options.cwd,
		agentDir: options.agentDir,
		authStorage,
		modelRegistry,
		resourceLoader,
		sessionManager,
		settingsManager,
		model: modelSelection.model,
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
