import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { registerAftkLoggingExtension, type AftkPiLoggingExtensionAPI } from "./logging.ts";

export default function registerAftkPiLoggingExtension(pi: ExtensionAPI): void {
  registerAftkLoggingExtension(pi as unknown as AftkPiLoggingExtensionAPI);
}
