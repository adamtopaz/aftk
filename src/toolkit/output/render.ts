import type { SourceRange } from "../server/protocol.ts";
import type { ToolkitToolError } from "./result.ts";

export function renderRange(range: SourceRange | null | undefined): string {
  if (range === null || range === undefined) {
    return "";
  }
  return ` (range: ${range.start.line}:${range.start.col}-${range.stop.line}:${range.stop.col})`;
}

export function renderGoals(goals: readonly string[]): string {
  if (goals.length === 0) {
    return "No goals.";
  }
  return goals.map((goal, index) => `${index + 1}. ${goal}`).join("\n\n");
}

export function renderBulletList(header: string, rows: readonly string[]): string {
  if (rows.length === 0) {
    return header;
  }
  return [header, ...rows].join("\n");
}

export function renderSection(title: string, body: string): string {
  return `${title}\n${"-".repeat(title.length)}\n${body}`;
}

export function joinSections(sections: readonly string[]): string {
  return sections.join("\n\n");
}

export function renderGenericErrorText(prefix: string, error: ToolkitToolError): string {
  const code = error.code !== undefined ? ` (code: ${String(error.code)})` : "";
  return `${prefix}: ${error.message}${code}`;
}
