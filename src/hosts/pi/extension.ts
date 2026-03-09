import { registerToolkitExtension, type PiExtensionAPILike } from "./index.ts";

export default function registerAftkToolkitExtension(pi: PiExtensionAPILike): void {
  registerToolkitExtension(pi, { cwd: process.cwd() });
}
