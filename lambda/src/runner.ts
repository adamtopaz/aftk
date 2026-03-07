import { existsSync, readFileSync } from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
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
	ModelRegistry,
	runPrintMode,
	SessionManager,
	SettingsManager,
} from "@mariozechner/pi-coding-agent";
import { Type, type Static } from "@sinclair/typebox";
import { Value } from "@sinclair/typebox/value";
import { createAFTKTools, type AFTKToolset } from "./aftk-tools";

export const LAMBDA_CONFIG_FILE_NAME = "lambda.json";
export const BUILTIN_TOOL_NAMES = ["read", "bash", "edit", "write", "grep", "find", "ls"] as const;

const BuiltInToolSchema = Type.Union(BUILTIN_TOOL_NAMES.map((name) => Type.Literal(name)));
const ThinkingLevelSchema = Type.Union([
	Type.Literal("off"),
	Type.Literal("minimal"),
	Type.Literal("low"),
	Type.Literal("medium"),
	Type.Literal("high"),
	Type.Literal("xhigh"),
]);

export const LambdaConfigSchema = Type.Object(
	{
		cwd: Type.Optional(Type.String({ minLength: 1 })),
		agentDir: Type.Optional(Type.String({ minLength: 1 })),
		model: Type.Optional(
			Type.Object(
				{
					provider: Type.String({ minLength: 1 }),
					id: Type.String({ minLength: 1 }),
				},
				{ additionalProperties: false },
			),
		),
		thinkingLevel: Type.Optional(ThinkingLevelSchema),
		builtInTools: Type.Optional(Type.Union([Type.Literal(false), Type.Array(BuiltInToolSchema)])),
	},
	{ additionalProperties: false },
);

export type LambdaConfig = Static<typeof LambdaConfigSchema>;
export type BuiltInToolName = (typeof BUILTIN_TOOL_NAMES)[number];

export interface ResolvedLambdaConfig {
	cwd: string;
	agentDir?: string;
	config: LambdaConfig;
}

export interface LoadedLambdaConfig extends ResolvedLambdaConfig {
	configPath: string;
	configDir: string;
}

export interface CreateLambdaSessionOptions {
	baseDir?: string;
	configPath?: string;
}

export interface LambdaSessionHandle extends ResolvedLambdaConfig {
	session: Awaited<ReturnType<typeof createAgentSession>>["session"];
	aftkToolset: AFTKToolset;
}

function expandHomeDir(rawPath: string): string {
	if (rawPath === "~") return os.homedir();
	if (rawPath.startsWith(`~${path.sep}`)) return path.join(os.homedir(), rawPath.slice(2));
	if (rawPath.startsWith("~/") || rawPath.startsWith("~\\")) return path.join(os.homedir(), rawPath.slice(2));
	return rawPath;
}

function resolveConfigPath(baseDir: string, rawPath: string | undefined): string | undefined {
	if (!rawPath) return undefined;
	const expanded = expandHomeDir(rawPath);
	return path.isAbsolute(expanded) ? expanded : path.resolve(baseDir, expanded);
}

function formatValidationPath(rawPath: string): string {
	if (!rawPath || rawPath === "/") return "(root)";
	return rawPath.replaceAll("/", ".").replace(/^\./, "");
}

function validateLambdaConfig(configLabel: string, parsed: unknown): LambdaConfig {
	const errors = [...Value.Errors(LambdaConfigSchema, parsed)];
	if (errors.length === 0) return parsed as LambdaConfig;

	const details = errors
		.slice(0, 8)
		.map((error) => `- ${formatValidationPath(error.path)}: ${error.message}`)
		.join("\n");
	const suffix = errors.length > 8 ? `\n- ...and ${errors.length - 8} more error(s)` : "";
	throw new Error(`Invalid ${configLabel}:\n${details}${suffix}`);
}

function loadConfigFile(configPath: string): LambdaConfig {
	let parsed: unknown;
	try {
		parsed = JSON.parse(readFileSync(configPath, "utf8"));
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		throw new Error(`Failed to read ${configPath}: ${message}`);
	}
	return validateLambdaConfig(configPath, parsed);
}

function resolveBuiltInTools(cwd: string, builtInTools: LambdaConfig["builtInTools"]) {
	if (builtInTools === false) return [];
	if (builtInTools === undefined) return createCodingTools(cwd);
	if (builtInTools.length === 0) return [];

	const tools = [];
	for (const toolName of builtInTools) {
		switch (toolName) {
			case "read":
				tools.push(createReadTool(cwd));
				break;
			case "bash":
				tools.push(createBashTool(cwd));
				break;
			case "edit":
				tools.push(createEditTool(cwd));
				break;
			case "write":
				tools.push(createWriteTool(cwd));
				break;
			case "grep":
				tools.push(createGrepTool(cwd));
				break;
			case "find":
				tools.push(createFindTool(cwd));
				break;
			case "ls":
				tools.push(createLsTool(cwd));
				break;
		}
	}

	return tools;
}

function createAuthStorage(agentDir: string | undefined): AuthStorage {
	if (!agentDir) return AuthStorage.create();
	return AuthStorage.create(path.join(agentDir, "auth.json"));
}

function createModelRegistry(authStorage: AuthStorage, agentDir: string | undefined): ModelRegistry {
	if (!agentDir) return new ModelRegistry(authStorage);
	return new ModelRegistry(authStorage, path.join(agentDir, "models.json"));
}

function resolveLambdaConfig(config: LambdaConfig, options: CreateLambdaSessionOptions = {}): ResolvedLambdaConfig {
	const configLabel = options.configPath ?? "lambda config";
	const validatedConfig = validateLambdaConfig(configLabel, config);
	const baseDir = options.baseDir ? path.resolve(options.baseDir) : process.cwd();
	const cwd = resolveConfigPath(baseDir, validatedConfig.cwd) ?? baseDir;
	const agentDir = resolveConfigPath(baseDir, validatedConfig.agentDir);

	return {
		cwd,
		agentDir,
		config: validatedConfig,
	};
}

async function createLambdaSessionFromResolved(config: ResolvedLambdaConfig): Promise<LambdaSessionHandle> {
	const settingsManager = SettingsManager.create(config.cwd, config.agentDir);
	const authStorage = createAuthStorage(config.agentDir);
	const modelRegistry = createModelRegistry(authStorage, config.agentDir);
	const model = config.config.model ? modelRegistry.find(config.config.model.provider, config.config.model.id) : undefined;
	if (config.config.model && !model) {
		throw new Error(`Model not found: ${config.config.model.provider}/${config.config.model.id}`);
	}

	const resourceLoader = new DefaultResourceLoader({
		cwd: config.cwd,
		agentDir: config.agentDir,
		settingsManager,
		noExtensions: true,
	});
	await resourceLoader.reload();

	const aftkToolset = createAFTKTools({ cwd: config.cwd });
	const builtInTools = resolveBuiltInTools(config.cwd, config.config.builtInTools);
	const { session } = await createAgentSession({
		cwd: config.cwd,
		agentDir: config.agentDir,
		authStorage,
		modelRegistry,
		resourceLoader,
		sessionManager: SessionManager.inMemory(config.cwd),
		settingsManager,
		model,
		thinkingLevel: config.config.thinkingLevel,
		tools: builtInTools,
		customTools: aftkToolset.tools,
	});

	return {
		...config,
		session,
		aftkToolset,
	};
}

export function findLambdaConfigFile(startDir = process.cwd()): string | undefined {
	let current = path.resolve(startDir);
	while (true) {
		const candidate = path.join(current, LAMBDA_CONFIG_FILE_NAME);
		if (existsSync(candidate)) return candidate;
		const parent = path.dirname(current);
		if (parent === current) return undefined;
		current = parent;
	}
}

export function loadLambdaConfig(startDir = process.cwd()): LoadedLambdaConfig {
	const configPath = findLambdaConfigFile(startDir);
	if (!configPath) {
		throw new Error(`Could not find ${LAMBDA_CONFIG_FILE_NAME}. Create it in your project root.`);
	}

	const config = loadConfigFile(configPath);
	const configDir = path.dirname(configPath);

	return {
		configPath,
		configDir,
		...resolveLambdaConfig(config, { baseDir: configDir, configPath }),
	};
}

export async function createLambdaSession(
	config: LambdaConfig,
	options: CreateLambdaSessionOptions = {},
): Promise<LambdaSessionHandle> {
	return await createLambdaSessionFromResolved(resolveLambdaConfig(config, options));
}

export async function closeLambdaSession(handle: LambdaSessionHandle): Promise<void> {
	handle.session.dispose();
	await handle.aftkToolset.shutdown(true);
}

export async function runLambdaPrompt(prompt: string, startDir = process.cwd()): Promise<void> {
	const trimmedPrompt = prompt.trim();
	if (trimmedPrompt.length === 0) {
		throw new Error("Missing prompt");
	}

	const loadedConfig = loadLambdaConfig(startDir);
	const handle = await createLambdaSessionFromResolved(loadedConfig);
	try {
		await runPrintMode(handle.session, {
			mode: "text",
			initialMessage: trimmedPrompt,
		});
	} finally {
		await closeLambdaSession(handle);
	}
}
