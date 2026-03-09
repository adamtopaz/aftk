import test from "node:test";
import assert from "node:assert/strict";
import { truncateText } from "../../../src/toolkit/output/truncate.ts";

test("truncateText preserves short text", () => {
  const result = truncateText("short text");
  assert.equal(result.text, "short text");
  assert.equal(result.truncation, undefined);
});

test("truncateText adds explicit truncation metadata", () => {
  const longText = Array.from({ length: 300 }, (_, index) => `line ${index + 1}`).join("\n");
  const result = truncateText(longText, { maxLines: 10, maxBytes: 1_000 });
  assert.ok(result.truncation !== undefined);
  assert.match(result.text, /Output truncated/);
  assert.equal(result.truncation?.displayedLines, 10);
  assert.equal(result.truncation?.originalLines, 300);
});
