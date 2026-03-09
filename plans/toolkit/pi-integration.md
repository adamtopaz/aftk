# Pi Integration Design

## Status

Component design/status document for mounting the toolkit into pi and pi-based SDK sessions.
This file now records the rationale for the pi integration that exists in code and the follow-on work that may still be added later.

Authoritative implementation docs live in:

- `docs/toolkit/overview.md`
- `docs/toolkit/library.md`
- `docs/aftk_setup.md`

## Component implementation status

- Overall status: Implemented (initial v1), with deferred follow-ons
- Implemented in code: Yes
- Last updated basis: the current pi host-adapter implementation in `src/hosts/pi/**`, the package metadata in `package.json`, the setup script in `lakefile.lean`, and `tests/toolkit/**`
- Main deferred follow-ons: any future additional host adapters, package-distribution hardening, or AI-layer-specific mounting helpers

The main pi-integration design questions in this file are now answered by the codebase.
Historical sections below may still describe pre-implementation expectations; treat them as design background only.

## Purpose

This document defines how the reusable toolkit should be mounted into:

- upstream interactive `pi` via an extension wrapper
- custom `@mariozechner/pi-coding-agent` SDK sessions

It is about:

- the boundary between reusable toolkit code and `pi`-specific code
- extension-wrapper design
- custom SDK integration design
- session-shutdown cleanup
- optional extension commands such as an explicit stop command
- package/discovery conventions for pi packages
- and which integration paths should be considered canonical vs optional

The goal is to preserve the earlier’s best architectural instinct — shared toolkit logic below a thin pi wrapper — while broadening it into a clearer and more flexible integration story for AFTK.

## Design goals

The pi integration layer should:

- remain thin and adapter-only rather than becoming the canonical implementation home
- support both:
  - upstream interactive `pi` extension loading,
  - and direct custom SDK session integration
- preserve explicit lifecycle cleanup for managed subprocesses
- make it easy to mount the toolkit into pi without forcing every user to re-register tools manually
- make it equally easy to embed the toolkit into a custom SDK session without requiring the full extension runtime when it is unnecessary
- follow current pi docs for extension/package conventions rather than only copying the earlier package layout
- keep package/discovery metadata clear enough for local testing, project use, and package distribution
- expose a configuration path for selecting which toolkit families to mount
- avoid coupling reusable toolkit modules directly to `ExtensionAPI`

## Scope and non-scope

### In scope

- upstream pi extension wrapper design
- custom SDK integration design for `createAgentSession(...)`
- cleanup hooks such as `session_shutdown`
- optional extension command design for explicit toolkit stop/cleanup
- package/discovery conventions relevant to pi integration
- module boundaries for `src/hosts/pi/`

### Out of scope

- reusable toolkit runtime, server client, or tool-family semantics themselves
- UI-heavy custom pi extension features unrelated to toolkit mounting
- theme/skill/prompt-template design
- non-pi host integrations
- exact test-case contents

Those are covered by companion documents.

## Research basis and design consequences

This integration plan is based on explicit research in both the AFTK worktrees and the pi docs/examples.

### Main-worktree reference points

Primary files studied:

- `../aftk/lambda/src/aftk-extension.ts`
- `../aftk/package.json`
- `../aftk/docs/aftk/README.md`

Important observations from the earlier integration:

- The current pi integration is deliberately thin.
- `aftk-extension.ts` simply:
  - creates the shared toolset with `createAFTKTools({ cwd: process.cwd() })`
  - hooks `session_shutdown`
  - registers an explicit stop command `aftk-extension-stop`
  - re-registers each tool from the shared toolset into `pi`
- The current shared toolset already exposes pi-compatible `ToolDefinition` values directly, and the extension wrapper merely forwards their name/label/description/parameters/execute fields into `pi.registerTool(...)`.
- The earlier package is already shaped as a pi package via:
  - `keywords: ["pi-package"]`
  - `pi.extensions: ["./lambda/src/aftk-extension.ts"]`
- The current wrapper treats `session_shutdown` as the cleanup hook for the managed hub process.

Main consequences for AFTK:

- the basic split between shared toolkit logic and a thin pi wrapper is correct and should be preserved;
- preserving an explicit stop command is reasonable;
- but AFTK should improve on the current design by:
  - moving pi-specific code out of the toolkit core into `src/hosts/pi/`,
  - supporting custom SDK sessions more explicitly,
  - and following current pi package guidance more deliberately.

### Pi documentation and example reference points

Primary docs studied:

- `/home/dev/.nvm/versions/node/v25.5.0/lib/node_modules/@mariozechner/pi-coding-agent/docs/extensions.md`
- `/home/dev/.nvm/versions/node/v25.5.0/lib/node_modules/@mariozechner/pi-coding-agent/docs/sdk.md`
- `/home/dev/.nvm/versions/node/v25.5.0/lib/node_modules/@mariozechner/pi-coding-agent/docs/packages.md`
- `/home/dev/.nvm/versions/node/v25.5.0/lib/node_modules/@mariozechner/pi-coding-agent/README.md`

Primary examples studied:

- `/home/dev/.nvm/versions/node/v25.5.0/lib/node_modules/@mariozechner/pi-coding-agent/examples/extensions/README.md`
- `/home/dev/.nvm/versions/node/v25.5.0/lib/node_modules/@mariozechner/pi-coding-agent/examples/extensions/shutdown-command.ts`
- `/home/dev/.nvm/versions/node/v25.5.0/lib/node_modules/@mariozechner/pi-coding-agent/examples/sdk/06-extensions.ts`
- `/home/dev/.nvm/versions/node/v25.5.0/lib/node_modules/@mariozechner/pi-coding-agent/examples/sdk/05-tools.ts`
- `/home/dev/.nvm/versions/node/v25.5.0/lib/node_modules/@mariozechner/pi-coding-agent/examples/sdk/README.md`

Important pi observations:

- `pi` extensions are ordinary TypeScript modules exporting a default function receiving `ExtensionAPI`.
- Extensions can register tools with `pi.registerTool(...)` and commands with `pi.registerCommand(...)`.
- `session_shutdown` is the documented lifecycle cleanup hook for extensions.
- `ctx.shutdown()` exists, but that is about shutting down pi itself, not just a managed subprocess.
- `pi.registerTool()` works during extension load and after startup.
- SDK sessions can load extensions through `DefaultResourceLoader` using:
  - `additionalExtensionPaths`
  - `extensionFactories`
- SDK sessions can also receive direct custom tools through `customTools` without using the full extension mechanism.
- Pi packages use `package.json` metadata under `pi`, commonly with:
  - `keywords: ["pi-package"]`
  - `pi.extensions: [...]`
- Current pi package docs recommend listing pi core imports such as:
  - `@mariozechner/pi-coding-agent`
  - `@sinclair/typebox`
  - `@mariozechner/pi-ai`

  in `peerDependencies` with `"*"` for package distribution, rather than bundling them.

Main consequences for AFTK:

- AFTK should support **two** first-class pi integration modes:
  1. extension-based mounting for upstream interactive pi and extension-style SDK use
  2. direct `customTools` mounting for custom SDK sessions that only need the tools
- AFTK should keep the extension wrapper thin and make `session_shutdown` the canonical cleanup hook there;
- AFTK should package the pi wrapper using current pi package conventions rather than inheriting the earlier package shape uncritically;
- and AFTK should not require every SDK user to load the full extension runtime if all they want is toolkit tools.

### Repository reference points

Primary files studied:

- `plans/toolkit/layout.md`
- `plans/toolkit/runtime.md`
- `plans/toolkit/server-client.md`
- `plans/toolkit/lean-tools.md`
- `plans/toolkit/knowledgebase-tools.md`
- `plans/toolkit/informal-tools.md`
- `plans/toolkit/output.md`

Current AFTK observations:

- The layout plan already places host adapters under:

```text
src/hosts/pi/
```

- The runtime/tool-family plans already distinguish:
  - reusable toolkit code,
  - managed state owned mainly by the Lean/server family,
  - and one-shot CLI families that do not need shutdown.
- The toolkit now has multiple families, not just the Lean-facing `aftk_*` tools.
- The toolkit output contract is host-agnostic and should stay that way.

Main consequences for AFTK:

- pi integration should mount one or more toolkit families into pi, not own their behavior;
- cleanup logic in the pi layer is mainly about managed families like the Lean/server client;
- and the pi adapter should be configurable enough to select family subsets while defaulting sensibly.

## Core integration decisions

The v1 pi-integration design should make the following choices explicit.

### 1. Keep `pi` integration outside the toolkit core

All `pi`-specific code should live under:

```text
src/hosts/pi/
```

The reusable toolkit core should not import `ExtensionAPI` or other extension-only types.

This preserves the architectural boundary settled elsewhere:

- reusable toolkit logic first
- host adapters second

### 2. Support two first-class pi integration modes

AFTK should support both of these modes explicitly.

#### Mode A: upstream pi extension wrapper

Use a standard pi extension entrypoint that can be:

- discovered from package metadata,
- loaded via `pi -e ...` for testing,
- or loaded by `DefaultResourceLoader` in SDK use.

This is the right mode when the host wants:

- extension lifecycle hooks,
- extension commands,
- and the same behavior users expect in interactive pi.

#### Mode B: direct SDK custom-tools mounting

Use a helper that produces pi-compatible custom tools for `createAgentSession({ customTools: [...] })` without requiring the full extension runtime.

This is the right mode when the host only wants:

- toolkit tools,
- explicit manual cleanup,
- and minimal integration overhead.

Both modes should be documented and supported.

### 3. The extension wrapper should be thin and mostly declarative

The upstream pi extension wrapper should do only a small set of things:

- create or obtain the selected toolkit family adapters
- register their tools into pi
- register any intentional extension commands
- hook `session_shutdown` for cleanup

It should **not**:

- own subprocess management logic,
- reimplement JSON-RPC handling,
- or reinterpret tool results.

### 4. The direct SDK path should not require the extension runtime

The toolkit should not force custom SDK users to route everything through `DefaultResourceLoader.extensionFactories` if all they need is a list of custom tools.

So AFTK should provide a direct SDK helper that can be used like this conceptually:

```ts
const integration = await createPiToolkitCustomTools(...)
const { session } = await createAgentSession({ customTools: integration.customTools, ... })
...
await integration.dispose()
```

This keeps SDK use straightforward and explicit.

### 5. Use `session_shutdown` as the canonical extension cleanup hook

Within the extension-based integration path, `session_shutdown` should be the canonical place to clean up toolkit-owned runtime state.

That is where the pi adapter should:

- stop managed hub processes
- clear extension-owned resources
- perform best-effort cleanup before pi exits

This preserves the earlier pattern and matches the pi extension docs.

### 6. Preserve an explicit stop command in the pi extension path

AFTK should preserve an explicit extension command analogous to the earlier:

- `aftk-extension-stop`

Its purpose is:

- stop the managed toolkit subprocess state owned by this extension runtime
- do **not** shut down pi itself
- leave the extension loaded and ready to lazily restart managed processes on later use if applicable

This command belongs only to the extension path, not to the direct `customTools` SDK path.

### 7. Do not use `ctx.shutdown()` for the stop command

The explicit stop command should stop toolkit-owned managed resources.
It should **not** call `ctx.shutdown()`, because that would request shutdown of the entire pi process.

The stop command is about AFTK/toolkit cleanup, not about quitting pi.

### 8. Default extension behavior should mount the stable toolkit families, but family selection should remain configurable

Once the toolkit families exist, the pi adapter should be able to mount:

- the Lean/server-backed family
- the knowledge-base family
- the informal family

A good v1 policy is:

- default to mounting all stable toolkit families
- allow adapter options to select a subset when needed for testing or specialized hosts

This matters because:

- only the Lean family owns meaningful managed process state today
- some hosts may want only Lean tools or only CLI-backed families

### 9. The pi adapter should preserve tool names, descriptions, parameters, and results from the toolkit families

The pi integration layer should not mutate the semantic tool contracts.
Its job is to register them into pi, not to redesign them.

So the adapter should preserve:

- tool names
- labels
- descriptions
- parameter schemas
- content/details/isError result semantics

If a host wants different names or descriptions, that should be an explicit higher-level choice, not something the default pi adapter does silently.

### 10. Package metadata should follow current pi package conventions

AFTK's pi integration should be packaged in a way that aligns with current pi docs.
That means the package should conceptually include:

- `keywords: ["pi-package"]`
- a `pi.extensions` entry pointing at the thin extension entrypoint

For a package intended to be loaded as a pi package, the documented pi core imports should be treated according to current pi package guidance, not merely copied from the earlier implementation’s package.json.

In practice that means AFTK should prefer current pi package conventions such as:

- pi core packages in `peerDependencies`
- local development/dev tooling in `devDependencies`

unless a later packaging-specific design note justifies a different arrangement.

### 11. Use `process.cwd()` as the extension wrapper’s default anchor for project resolution

The earlier extension passes:

```ts
{ cwd: process.cwd() }
```

when creating the shared toolset.
That remains the right default for the extension wrapper in AFTK as well.

The reusable runtime still owns project-root discovery from that anchor.
The pi extension should not introduce its own extra project-root logic.

### 12. Prefer registration at extension load time for the default wrapper

Because the toolkit family set is expected to be static within one runtime, the default extension wrapper should register its tools during extension load rather than waiting for `session_start`.

Reasons:

- simpler implementation
- immediate tool availability
- matches the earlier wrapper

The pi docs allow dynamic registration later, but AFTK does not need that complexity for the default adapter.

### 13. SDK sessions that want extension semantics may still load the extension wrapper through `DefaultResourceLoader`

Even though the direct `customTools` path should exist, AFTK should also document the extension-based SDK pattern for hosts that want:

- extension commands,
- lifecycle hooks,
- or parity with interactive pi extension behavior.

That path should use documented SDK mechanisms such as:

- `DefaultResourceLoader({ additionalExtensionPaths: [...] })`
- `DefaultResourceLoader({ extensionFactories: [...] })`

This keeps the two integration modes complementary rather than mutually exclusive.

## Integration modes in detail

## Mode A — upstream pi extension wrapper

This is the standard integration for interactive pi and pi-package installation.

### Extension entrypoint

The extension entrypoint should live at something like:

```text
src/hosts/pi/extension.ts
```

and export:

```ts
default function (pi: ExtensionAPI) { ... }
```

This is the file referenced from package metadata.

### Package metadata

A good conceptual package shape is:

```json
{
  "keywords": ["pi-package"],
  "pi": {
    "extensions": ["./src/hosts/pi/extension.ts"]
  }
}
```

This mirrors the documented pi package approach, but with AFTK's new file layout.

### Local testing and discovery

The extension should be usable through the normal pi mechanisms:

- `pi -e ./src/hosts/pi/extension.ts` for quick testing
- package installation via pi package metadata
- auto-discovery if placed in `.pi/extensions/` or `~/.pi/agent/extensions/`

The package/discovery mechanism is not the semantic contract of the toolkit, but the adapter should fit naturally into documented pi workflows.

## Mode B — direct custom SDK mounting

This is the preferred path for custom SDK sessions that only need tools.

### Conceptual usage shape

A good conceptual usage pattern is:

```ts
const integration = await createPiToolkitCustomTools({ cwd: myCwd })
const { session } = await createAgentSession({
  cwd: myCwd,
  customTools: integration.customTools,
  ...
})

try {
  await session.prompt("...")
} finally {
  await integration.dispose()
  session.dispose()
}
```

### Why this path matters

This path avoids:

- spinning up the full extension runtime when it is unnecessary
- forcing SDK users to think in terms of extension files and resource discovery
- requiring commands/hooks when only tools are desired

### What the helper should return

A good helper should return at least:

- `customTools`
- `dispose()` or equivalent cleanup hook

Potentially also:

- metadata about which families were mounted
- access to underlying family handles for advanced hosts, if later needed

## Optional Mode C — SDK sessions using the extension runtime

This is an optional but supported pattern.

### Usage shape

A host can load the same extension through `DefaultResourceLoader`, conceptually like:

```ts
const loader = new DefaultResourceLoader({
  additionalExtensionPaths: ["./src/hosts/pi/extension.ts"]
})
await loader.reload()
const { session } = await createAgentSession({ resourceLoader: loader, ... })
```

or through:

```ts
extensionFactories: [(pi) => registerToolkitExtension(pi, options)]
```

### When to prefer this mode

Use this mode when the SDK host wants parity with the extension path, including:

- extension commands such as `aftk-extension-stop`
- extension lifecycle hooks such as `session_shutdown`
- or later extension-only UI behavior if added

This mode is valid, but AFTK should not require it for all SDK use.

## Extension wrapper behavior

The default extension wrapper should be straightforward.

### Startup behavior

On load, the wrapper should:

1. create the selected toolkit family adapters using the current working directory as the anchor
2. register their tools into pi
3. register the explicit stop command
4. install the `session_shutdown` cleanup hook

### Cleanup behavior

On `session_shutdown`, the wrapper should:

- call aggregate toolkit cleanup for any managed families
- ignore or handle already-stopped state idempotently
- avoid emitting noisy UI unless there is a real failure worth surfacing

### Stop-command behavior

The explicit stop command should:

- perform the same aggregate toolkit cleanup action as `session_shutdown`
- be safe to call repeatedly
- use `ctx.ui.notify(...)` when UI is available to confirm that cleanup occurred
- not shut down pi

### Restart behavior after stop

If the user later calls a tool that depends on a managed runtime such as the Lean hub, the lower toolkit layers may lazily restart it according to their own runtime policies.
The pi adapter should not add special restart logic.

## Family-selection policy

The pi integration layer should be able to select which toolkit families to mount.

### Default policy

A sensible default once all families exist is:

- Lean tools: enabled
- knowledge-base tools: enabled
- informal tools: enabled

### Configurable policy

The adapter should also support options such as:

- `families: { lean?: boolean, knowledgebase?: boolean, informal?: boolean }`

or an equivalent allowlist/selection mechanism.

This is useful for:

- tests
- minimal hosts
- phased rollout while some families are still unstable

### Cleanup implications

Family selection affects cleanup only in one main way:

- CLI-backed families are stateless per call
- managed Lean/server families own meaningful cleanup state

So the aggregate cleanup helper should simply compose the cleanup of enabled managed families and ignore purely one-shot families.

## Recommended adapter API surfaces

Within `src/hosts/pi/`, AFTK should expose at least two helper surfaces.

### 1. Extension registration helper

A good helper name is conceptually:

```ts
registerToolkitExtension(pi, options?)
```

Responsibilities:

- create selected toolkit family adapters
- register tools into pi
- register the stop command
- hook `session_shutdown`
- return an optional small handle if useful for tests

This helper is what the default extension entrypoint should call.

### 2. Direct SDK custom-tools helper

A good helper name is conceptually:

```ts
createPiToolkitCustomTools(options?)
```

Responsibilities:

- create selected toolkit family adapters
- convert them into pi-compatible `customTools`
- expose `dispose()` for cleanup

This helper is what direct SDK integrations should use.

### 3. Optional aggregate helper

If useful, the pi adapter may also expose a higher-level helper returning both capabilities, conceptually like:

```ts
createPiToolkitIntegration(options?)
```

with fields such as:

- `customTools`
- `registerIntoExtension(pi)`
- `dispose()`

This is optional.
The main important point is that both extension-style and direct SDK integration paths are available.

## Package and dependency guidance

The pi integration layer should follow current pi package guidance.

### Package metadata

The package should be identifiable as a pi package when that is the intended distribution mode.
That means:

- `keywords: ["pi-package"]`
- `pi.extensions` pointing to the thin wrapper entrypoint

### Core pi imports

If AFTK package imports pi core packages such as:

- `@mariozechner/pi-coding-agent`
- `@sinclair/typebox`
- `@mariozechner/pi-ai`

then the package should follow the current pi package guidance about how those are declared for distribution.

A good v1 rule is:

- pi core packages in `peerDependencies`
- development/build/test support in `devDependencies`
- no bundling of pi core packages into the published pi package

### Why this is an integration concern

This is not just a packaging footnote.
It affects whether downstream pi installs and SDK integrations get one clean copy of the expected pi runtime types and APIs.

## Relationship to toolkit-owned tool definitions

The pi adapter should consume toolkit-owned tool-family definitions and adapt them to pi.
The exact internal tool-definition type can still be finalized during implementation, but the boundary should be clear.

### If toolkit families are host-agnostic

If the toolkit families use a host-agnostic internal tool-definition shape, the pi adapter should convert that shape into:

- `pi.registerTool(...)` inputs for the extension path
- `customTools` definitions for the direct SDK path

### If toolkit families already expose pi-compatible tool definitions

If implementation pressure leads the toolkit families to expose pi-compatible tool definitions directly, the adapter should still remain thin and should not add semantic logic.

Either way, the architectural rule remains the same:

- toolkit families own semantics
- pi adapter owns mounting

## Error and diagnostics policy in the pi adapter

The pi adapter should keep its own logic minimal.

### Tool execution errors

Tool execution errors should normally be returned by the toolkit tool result itself, not handled specially by the pi adapter.

### Registration/startup failures

If the extension wrapper fails during startup because toolkit initialization is impossible, it should fail clearly rather than partially registering a broken set of tools.

### Cleanup failures

If cleanup fails during `session_shutdown` or the stop command:

- best-effort cleanup should still continue for the remaining families
- failures may be surfaced to UI when appropriate in command handlers
- but the adapter should avoid turning cleanup into noisy normal-path behavior

## Relationship to built-in pi tools

The toolkit tools are additional custom tools.
They do not replace pi’s built-in coding tools by default.

That means:

- direct SDK integrations may still include built-in tools through `tools: [...]`
- toolkit tools should usually be supplied through `customTools`
- extension registration should just add the toolkit tools alongside the built-ins available in that pi session

The pi adapter should not own built-in tool selection policy.
That belongs to the host session configuration.

## Recommended module responsibilities

Within the layout settled in `plans/toolkit/layout.md`, the pi integration should likely be refined as follows.

### `src/hosts/pi/index.ts`

This module should own:

- exported helper functions for:
  - extension registration
  - direct SDK custom-tools creation
- small pi-specific adapter types if needed
- family-selection option types for the pi host layer

It should depend on:

- the reusable toolkit family factories
- pi SDK/extension types

It should not own:

- runtime/process logic
- server protocol logic
- tool-family semantics

### `src/hosts/pi/extension.ts`

This module should own:

- the default extension entrypoint referenced by package metadata
- one small default call into `registerToolkitExtension(...)`
- the conventional `cwd: process.cwd()` default anchor

It should be extremely small.

## Boundaries and anti-patterns

The pi integration layer should explicitly avoid the following mistakes.

### 1. No toolkit core logic in the extension wrapper

If the extension file contains process management, protocol parsing, or major result-formatting logic, the boundary is wrong.

### 2. No forcing all SDK users through the extension runtime

Direct `customTools` integration should remain available.

### 3. No use of `ctx.shutdown()` for the stop command

Stopping AFTK/toolkit resources is not the same as shutting down pi.

### 4. No package/discovery assumptions hardcoded into reusable toolkit modules

Auto-discovery locations, `pi.extensions`, and similar concerns belong in the pi adapter/package layer.

### 5. No silent renaming or semantic reshaping of toolkit tools in the adapter

The adapter should mount the toolkit surface faithfully.

### 6. No cleanup hook logic scattered across multiple event handlers without reason

`session_shutdown` should be the canonical cleanup hook for the extension path.

### 7. No pretending that one-shot CLI families need managed shutdown state

Only managed families should participate meaningfully in cleanup.

## Initial implementation checklist for this pi-integration design

Before the pi integration layer can be considered in place, AFTK should reach at least this baseline:

- `src/hosts/pi/` exists and is clearly separate from the toolkit core
- a thin default extension entrypoint exists
- package metadata points `pi.extensions` at that thin entrypoint
- the extension path mounts the selected toolkit families and hooks `session_shutdown`
- an explicit stop command exists for managed toolkit cleanup
- a direct SDK custom-tools helper exists and does not require the extension runtime
- cleanup is explicit and idempotent for managed families
- the pi adapter preserves toolkit tool names, parameters, and result semantics faithfully
- package/dependency conventions follow current pi documentation rather than only the earlier historical package layout

## Summary

AFTK should preserve the earlier architectural pattern of:

- shared toolkit logic below,
- thin pi wrapper above.

But it should broaden that pattern into a clearer pi integration story with **two first-class modes**:

1. a standard upstream pi extension wrapper for interactive use and package installation
2. a direct SDK custom-tools helper for embedded sessions that do not need the full extension runtime

In both cases, the pi layer should stay thin.
It should:

- mount selected toolkit families into pi,
- preserve their names and results,
- hook `session_shutdown` for cleanup in the extension path,
- offer an explicit `aftk-extension-stop` command for managed resource cleanup,
- and follow current pi package conventions for packaging and discovery.

That gives AFTK a clean, documented, future-proof way to use the toolkit from both upstream pi and custom SDK sessions without collapsing host-specific concerns back into the toolkit core.
