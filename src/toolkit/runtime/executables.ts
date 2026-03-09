import * as path from "node:path";

export interface CommandSpecInput {
  command: string;
  args?: string[];
  cwd?: string;
  env?: NodeJS.ProcessEnv;
  label?: string;
}

export interface ResolvedCommandSpec {
  command: string;
  args: string[];
  cwd: string;
  env: NodeJS.ProcessEnv;
  label: string;
}

export interface ToolkitExecutableOverrides {
  hub: CommandSpecInput;
  knowledgebase: CommandSpecInput;
  informal: CommandSpecInput;
}

export interface ToolkitExecutableSpecs {
  hub: ResolvedCommandSpec;
  knowledgebase: ResolvedCommandSpec;
  informal: ResolvedCommandSpec;
}

export interface ResolveExecutableSpecsOptions {
  cwd: string;
  projectRoot: string;
  env: NodeJS.ProcessEnv;
  overrides?: Partial<ToolkitExecutableOverrides>;
}

function resolvePathLike(input: string, baseDir: string): string {
  if (path.isAbsolute(input)) {
    return input;
  }
  if (input.includes(path.sep) || input.includes("/")) {
    return path.resolve(baseDir, input);
  }
  return input;
}

function resolveCommandSpec(
  defaultSpec: CommandSpecInput,
  override: CommandSpecInput | undefined,
  options: ResolveExecutableSpecsOptions,
  defaultLabel: string,
): ResolvedCommandSpec {
  const merged: CommandSpecInput = {
    ...defaultSpec,
    ...override,
    args: override?.args ?? defaultSpec.args ?? [],
    env: {
      ...options.env,
      ...defaultSpec.env,
      ...override?.env,
    },
  };

  const cwd = merged.cwd ? path.resolve(options.cwd, merged.cwd) : options.projectRoot;
  return {
    command: resolvePathLike(merged.command, options.cwd),
    args: [...(merged.args ?? [])],
    cwd,
    env: merged.env ?? options.env,
    label: merged.label ?? defaultLabel,
  };
}

export function resolveToolkitExecutableSpecs(options: ResolveExecutableSpecsOptions): ToolkitExecutableSpecs {
  const defaults: ToolkitExecutableOverrides = {
    hub: {
      command: "lake",
      args: ["exe", "aftk_server"],
      label: "lake exe aftk_server",
    },
    knowledgebase: {
      command: "lake",
      args: ["exe", "aftk", "knowledgebase"],
      label: "lake exe aftk knowledgebase",
    },
    informal: {
      command: "lake",
      args: ["exe", "aftk", "informal"],
      label: "lake exe aftk informal",
    },
  };

  return {
    hub: resolveCommandSpec(defaults.hub, options.overrides?.hub, options, defaults.hub.label ?? "hub"),
    knowledgebase: resolveCommandSpec(
      defaults.knowledgebase,
      options.overrides?.knowledgebase,
      options,
      defaults.knowledgebase.label ?? "knowledgebase",
    ),
    informal: resolveCommandSpec(
      defaults.informal,
      options.overrides?.informal,
      options,
      defaults.informal.label ?? "informal",
    ),
  };
}
