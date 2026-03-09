export interface ToolkitTextTruncationPolicy {
  maxLines: number;
  maxBytes: number;
}

export interface ToolkitTextTruncationInfo {
  textTruncated: boolean;
  originalLines: number;
  displayedLines: number;
  originalBytes: number;
  displayedBytes: number;
}

export const DEFAULT_TEXT_TRUNCATION_POLICY: ToolkitTextTruncationPolicy = {
  maxLines: 200,
  maxBytes: 20 * 1024,
};

function lineCount(text: string): number {
  return text.length === 0 ? 0 : text.split(/\r?\n/).length;
}

export function truncateText(
  text: string,
  policy: ToolkitTextTruncationPolicy = DEFAULT_TEXT_TRUNCATION_POLICY,
): { text: string; truncation?: ToolkitTextTruncationInfo } {
  const originalLines = lineCount(text);
  const originalBytes = Buffer.byteLength(text);

  let rendered = text;
  let lines = rendered.split(/\r?\n/);
  if (lines.length > policy.maxLines) {
    rendered = lines.slice(0, policy.maxLines).join("\n");
    lines = rendered.split(/\r?\n/);
  }

  while (Buffer.byteLength(rendered) > policy.maxBytes && rendered.length > 0) {
    rendered = rendered.slice(0, Math.max(0, rendered.length - 256));
  }

  const displayedLines = lineCount(rendered);
  const displayedBytes = Buffer.byteLength(rendered);
  if (displayedLines === originalLines && displayedBytes === originalBytes) {
    return { text };
  }

  const notice = `\n\n[Output truncated: showing ${displayedLines} of ${originalLines} lines (${displayedBytes} of ${originalBytes} bytes)]`;
  return {
    text: rendered + notice,
    truncation: {
      textTruncated: true,
      originalLines,
      displayedLines,
      originalBytes,
      displayedBytes,
    },
  };
}
