import type { ToolkitToolResult } from "../output/result.ts";

export type ToolkitJsonSchema = Record<string, unknown>;

export interface ToolkitToolDefinition<Params = unknown, Result = unknown> {
  name: string;
  label: string;
  description: string;
  parameters: ToolkitJsonSchema;
  execute: (
    toolCallId: string,
    params: Params,
    signal?: AbortSignal,
    onUpdate?: (update: unknown) => void,
    context?: unknown,
  ) => Promise<ToolkitToolResult<Result>>;
}

export interface ToolkitManagedToolset {
  tools: ToolkitToolDefinition[];
  shutdown: (graceful?: boolean) => Promise<void>;
}

export interface ToolkitStatelessToolset {
  tools: ToolkitToolDefinition[];
}

export interface ToolkitFamilySelection {
  lean?: boolean;
  knowledgebase?: boolean;
  informal?: boolean;
}

export class ToolInputError extends Error {
  readonly category = "usage";
  readonly code = "tool.invalidParams";

  constructor(message: string) {
    super(message);
    this.name = "ToolInputError";
  }
}

export const Schema = {
  string(description: string, extra: Record<string, unknown> = {}): ToolkitJsonSchema {
    return { type: "string", description, ...extra };
  },

  integer(description: string, extra: Record<string, unknown> = {}): ToolkitJsonSchema {
    return { type: "integer", description, ...extra };
  },

  boolean(description: string, extra: Record<string, unknown> = {}): ToolkitJsonSchema {
    return { type: "boolean", description, ...extra };
  },

  array(items: ToolkitJsonSchema, description: string, extra: Record<string, unknown> = {}): ToolkitJsonSchema {
    return { type: "array", items, description, ...extra };
  },

  enum(values: readonly string[], description: string): ToolkitJsonSchema {
    return { type: "string", enum: [...values], description };
  },

  object(
    properties: Record<string, ToolkitJsonSchema>,
    required: readonly string[] = [],
    description?: string,
  ): ToolkitJsonSchema {
    return {
      type: "object",
      description,
      additionalProperties: false,
      properties,
      required: [...required],
    };
  },
};

function expectRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new ToolInputError(`Tool parameters must be an object.`);
  }
  return value as Record<string, unknown>;
}

export function requireString(params: unknown, field: string): string {
  const record = expectRecord(params);
  const value = record[field];
  if (typeof value !== "string") {
    throw new ToolInputError(`Parameter '${field}' must be a string.`);
  }
  return value;
}

export function optionalString(params: unknown, field: string): string | undefined {
  const record = expectRecord(params);
  const value = record[field];
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== "string") {
    throw new ToolInputError(`Parameter '${field}' must be a string when provided.`);
  }
  return value;
}

export function requirePositiveInteger(params: unknown, field: string): number {
  const record = expectRecord(params);
  const value = record[field];
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw new ToolInputError(`Parameter '${field}' must be an integer >= 1.`);
  }
  return value;
}

export function optionalBoolean(params: unknown, field: string): boolean | undefined {
  const record = expectRecord(params);
  const value = record[field];
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== "boolean") {
    throw new ToolInputError(`Parameter '${field}' must be a boolean when provided.`);
  }
  return value;
}

export function requireNonEmptyString(params: unknown, field: string): string {
  const value = requireString(params, field).trim();
  if (value.length === 0) {
    throw new ToolInputError(`Parameter '${field}' must be a non-empty string.`);
  }
  return value;
}

export function requireStringArray(
  params: unknown,
  field: string,
  options: { nonEmpty?: boolean; itemNonEmpty?: boolean } = {},
): string[] {
  const record = expectRecord(params);
  const value = record[field];
  if (!Array.isArray(value) || !value.every((item) => typeof item === "string")) {
    throw new ToolInputError(`Parameter '${field}' must be an array of strings.`);
  }
  if (options.nonEmpty === true && value.length === 0) {
    throw new ToolInputError(`Parameter '${field}' must be a non-empty array.`);
  }
  if (options.itemNonEmpty === true && value.some((item) => item.trim().length === 0)) {
    throw new ToolInputError(`Parameter '${field}' may not contain empty strings.`);
  }
  return value;
}

export function optionalEnum<T extends string>(params: unknown, field: string, values: readonly T[]): T | undefined {
  const value = optionalString(params, field);
  if (value === undefined) {
    return undefined;
  }
  if (!values.includes(value as T)) {
    throw new ToolInputError(`Parameter '${field}' must be one of: ${values.join(", ")}.`);
  }
  return value as T;
}

export function normalizeToolPath(rawPath: string): string {
  return rawPath.startsWith("@") ? rawPath.slice(1) : rawPath;
}

export function enabledFamilies(selection: ToolkitFamilySelection | undefined): Required<ToolkitFamilySelection> {
  return {
    lean: selection?.lean ?? true,
    knowledgebase: selection?.knowledgebase ?? true,
    informal: selection?.informal ?? true,
  };
}
