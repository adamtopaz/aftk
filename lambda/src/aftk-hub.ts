import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { createAFTKTools } from "./aftk-tools";

export default function (pi: ExtensionAPI) {
	const toolset = createAFTKTools({ cwd: process.cwd() });

	pi.on("session_shutdown", async () => {
		await toolset.shutdown(true);
	});

	pi.registerCommand("aftk-hub-stop", {
		description: "Stop the local aftk_server process managed by this extension",
		handler: async (_args, ctx) => {
			await toolset.shutdown(true);
			if (ctx.hasUI) {
				ctx.ui.notify("AFTK hub stopped", "info");
			}
		},
	});

	for (const tool of toolset.tools) {
		pi.registerTool({
			name: tool.name,
			label: tool.label,
			description: tool.description,
			parameters: tool.parameters,
			async execute(toolCallId, params, signal, _onUpdate, ctx) {
				return await tool.execute(toolCallId, params, signal, _onUpdate, ctx);
			},
		});
	}
}
