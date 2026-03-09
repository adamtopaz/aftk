import { existsSync, statSync } from "node:fs";
import * as path from "node:path";
import { ToolkitConfigError } from "./errors.ts";

export interface ResolveProjectRootOptions {
  cwd: string;
  projectRoot?: string;
}

function hasLakefile(dir: string): boolean {
  return existsSync(path.join(dir, "lakefile.toml")) || existsSync(path.join(dir, "lakefile.lean"));
}

function isDirectory(dir: string): boolean {
  try {
    return statSync(dir).isDirectory();
  } catch {
    return false;
  }
}

export function findProjectRoot(startDir: string): string | null {
  let current = path.resolve(startDir);
  while (true) {
    if (hasLakefile(current)) {
      return current;
    }
    const parent = path.dirname(current);
    if (parent === current) {
      return null;
    }
    current = parent;
  }
}

export function resolveProjectRoot(options: ResolveProjectRootOptions): string {
  const cwd = path.resolve(options.cwd);
  if (options.projectRoot !== undefined) {
    const explicitRoot = path.resolve(cwd, options.projectRoot);
    if (!isDirectory(explicitRoot)) {
      throw new ToolkitConfigError(`Explicit project root does not exist or is not a directory: ${explicitRoot}`, {
        cwd,
      });
    }
    return explicitRoot;
  }

  const discovered = findProjectRoot(cwd);
  if (discovered === null) {
    throw new ToolkitConfigError(`Could not find a Lean project root above ${cwd}.`, {
      cwd,
    });
  }

  return discovered;
}
