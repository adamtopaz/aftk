#!/usr/bin/env bun

import { runLambdaPrompt } from "./runner";

process.title = "lambda";

function printUsage(): void {
	console.error('Usage: bun run lambda "<prompt>"');
}

async function run(): Promise<void> {
	const prompt = process.argv.slice(2).join(" ").trim();
	if (prompt.length === 0) {
		printUsage();
		throw new Error("Missing prompt");
	}

	await runLambdaPrompt(prompt);
}

run().catch((error) => {
	const message = error instanceof Error ? error.message : String(error);
	console.error(`lambda error: ${message}`);
	process.exitCode = 1;
});
