# Toolkit Library Layout

## Status

Component design/status document for the TypeScript package and module layout of the toolkit layer.
This file now mainly records the rationale for the layout that exists in code and the follow-on work that remains possible.

Authoritative implementation docs live in:

- `docs/toolkit/overview.md`
- `docs/toolkit/library.md`

## Component implementation status

- Overall status: Implemented (initial v1), with deferred follow-ons
- Implemented in code: Yes
- Last updated basis: the current toolkit package layout in `src/index.ts`, `src/toolkit/**`, `src/hosts/pi/**`, `index.ts`, `package.json`, `tsconfig.json`, and `tests/toolkit/**`
- Main deferred follow-ons: any future composite-tool area or additional host adapters beyond the current package structure

The layout questions this file was written to settle are now answered in the repository.
The historical sections below may still discuss the earlier placeholder scaffold; read those as design background rather than as current-state descriptions.

## Purpose

This document defines how the rewrite toolkit layer should be laid out in the TypeScript source tree.
It is about:

- package structure
- module boundaries
- public export surfaces
- dependency direction between toolkit subareas
- the separation between reusable toolkit code and host adapters
- and the matching TypeScript test-tree layout

The goal is to prevent the rewrite from reproducing the main-worktree situation where nearly all toolkit logic lives in one TypeScript file.
AFTK should instead begin from a clear library layout that can support:

- a managed server client,
- CLI-backed knowledge-base and informal integrations,
- multiple tool families,
- thin `pi` adapters,
- and real TypeScript-side testing.

## Design goals

The layout should:

- keep reusable toolkit library code separate from `pi`-specific adapter code
- avoid a single oversized file as the home for runtime helpers, server client logic, schemas, and tool definitions
- give the rewrite’s three lower-layer integration styles clear homes:
  - managed server protocol,
  - knowledge-base CLI bridge,
  - informal CLI bridge
- make public exports deliberate and curated rather than exposing internal files accidentally
- fit the rewrite’s broader architecture rather than inheriting the main-worktree `lambda/src` layout uncritically
- leave a natural home for cross-tool output/result normalization
- keep TypeScript test code easy to organize without colliding confusingly with the existing Lean test tree
- support the expected single-package workflow for both reusable library use and `pi` integration

## Scope and non-scope

### In scope

- TypeScript source-tree layout in the repository
- package-root entrypoint policy
- public export policy
- recommended submodule groupings for runtime, server, lower-layer CLI bridges, tool families, and host adapters
- test-tree layout for toolkit code
- high-level package/tsconfig implications that follow from the chosen layout

### Out of scope

- exact runtime process-management behavior
- exact server-client request/response API details
- exact tool parameter/result schemas
- exact output normalization rules
- exact test-case contents
- exact dependency versions

Those are covered by the companion design docs.

## Research basis and design consequences

This layout plan is based on explicit research in both worktrees.

### Main-worktree reference points

Files studied:

- `../aftk/lambda/src/aftk-tools.ts`
- `../aftk/lambda/src/aftk-extension.ts`
- `../aftk/package.json`
- `../aftk/tsconfig.json`
- `../aftk/docs/aftk/README.md`

Key layout observations:

- The current toolkit implementation is concentrated almost entirely in `lambda/src/aftk-tools.ts`.
- The current `lambda/src/aftk-extension.ts` is a good example of the right **architectural split**:
  - shared toolkit logic below,
  - thin `pi` adapter above.
- The main-worktree layout is still strongly shaped by the `pi` extension packaging use case.
- The main-worktree TypeScript surface is effectively a **single tool family plus extension wrapper**, not a broader toolkit library.

Main consequence for the rewrite:

- we should preserve the **thin adapter over shared toolkit code** pattern,
- but we should **not** preserve the one-large-file structure or the `lambda/src`-centric architecture as the default layout.

### Repository reference points

Files studied:

- `index.ts`
- `package.json`
- `tsconfig.json`
- `docs/architecture.md`
- `plans/toolkit.md`
- `plans/server/layout.md`

Key layout observations:

- At the time of the original research, the repository had no toolkit structure at all.
- The original repository-root `index.ts` was only a Bun-style placeholder.
- At that stage, `package.json` and `tsconfig.json` still signaled scaffold defaults rather than deliberate toolkit architecture.
  Concretely:
  - `package.json` still points `module` at the root `index.ts` and only advertises Bun-oriented scaffolding such as `@types/bun`;
  - `tsconfig.json` still uses settings like `module: "Preserve"`, `moduleResolution: "bundler"`, `allowJs`, and `jsx`, which are not meaningful signals of the intended toolkit library shape.
- `lakefile.lean` defines the real lower-layer executables the toolkit targets, so the TypeScript package layout should be organized around those integration boundaries rather than around the placeholder Bun entrypoint.
- The rewrite’s first three layers already have strong library/layout discipline in Lean, especially visible in `docs/architecture.md` and `plans/server/layout.md`.
- The toolkit layer must cover more than the main-worktree server wrapper alone:
  - server integration,
  - knowledge-base CLI integration,
  - informal CLI integration,
  - and host adapters.

Main consequence for the rewrite:

- the toolkit should be laid out as a **real TypeScript library** under a proper `src/` tree,
- with explicit homes for reusable runtime code, lower-layer clients, tool families, output shaping, and host adapters.

## Core layout decisions

The v1 toolkit layout should make the following decisions explicit.

### 1. Use a `src/` tree as the implementation home

The rewrite toolkit should live under a conventional TypeScript source root:

```text
src/
```

not in the repository root and not under `lambda/`.

Reasoning:

- the rewrite toolkit is broader than a `pi` extension package,
- it should read as a library first,
- and the `lambda/src` naming from the main worktree would misleadingly center the adapter rather than the toolkit.

### 2. Treat the package as one package with multiple entrypoints

The rewrite does **not** need multiple npm packages for v1.
A single package with curated entrypoints is enough.

That package should expose at least:

- a library root entrypoint for reusable toolkit code
- a `pi` adapter entrypoint
- a `pi` extension file path for package metadata

This keeps the implementation operationally simple while preserving the library/adapter split.

### 3. Put reusable toolkit code under `src/toolkit/`

All non-host-specific toolkit code should live under:

```text
src/toolkit/
```

This should be the conceptual root for:

- runtime/process helpers
- server client code
- knowledge-base CLI bridge code
- informal CLI bridge code
- output normalization helpers
- tool-family factories

### 4. Put host adapters outside the toolkit core

Host adapters should live outside `src/toolkit/`, under something like:

```text
src/hosts/pi/
```

This makes the boundary visible in the file tree itself:

- `src/toolkit/...` is host-agnostic reusable code
- `src/hosts/...` is mounting code for a specific host environment

### 5. Keep one curated public library root

The package should have one library root entrypoint:

```text
src/index.ts
```

That file should re-export the intended stable toolkit surface.
It should not become an implementation dumping ground.

### 6. Do not promise deep internal file paths as public API

Consumers should import from curated entrypoints rather than from arbitrary internal files.
Internal modules under `src/toolkit/...` should be free to evolve.

So the stable public API should be defined by:

- `src/index.ts`
- optional curated subpath exports such as `./pi`
- and the `pi` extension entrypoint path itself

not by every file inside `src/toolkit/`.

### 7. Keep low-level clients below tool-family factories

The layout should separate:

- lower-layer clients and process/CLI bridges
- from the agent-facing tool definitions built on top of them.

This is important for:

- testing lower-level behavior directly,
- using the toolkit from custom TypeScript integrations without the `pi` tool abstraction,
- and avoiding the main-worktree pattern where client and tool logic are intertwined in one file.

### 8. Give output/result normalization its own home

Cross-tool result shaping should not be buried inside individual tool-family modules.
It needs a dedicated place in the layout because it will be shared across:

- server-backed Lean tools,
- knowledge-base CLI-backed tools,
- and informal CLI-backed tools.

### 9. Put TypeScript test code under `tests/toolkit/`

The repository already uses `tests/` for Lean fixtures and golden files.
TypeScript-side toolkit tests should therefore live under:

```text
tests/toolkit/
```

This keeps them close to existing fixture roots while making their ownership explicit.

### 10. Replace the root placeholder `index.ts`

The current root `index.ts` should stop being the implementation home.
The preferred end state is:

- `src/index.ts` as the real library entrypoint,
- no meaningful toolkit implementation at the repository root.

If a short-lived migration shim is useful, a root `index.ts` may temporarily re-export from `src/index.ts`.
But that should be transitional only.

## Recommended initial repository layout

A good initial layout for the toolkit layer is:

```text
package.json
tsconfig.json
src/
  index.ts
  toolkit/
    runtime/
      options.ts
      project-root.ts
      executables.ts
      errors.ts
      subprocess.ts
      cli.ts
    output/
      result.ts
      truncate.ts
      render.ts
    server/
      protocol.ts
      client.ts
    knowledgebase/
      client.ts
    informal/
      client.ts
    tools/
      lean.ts
      knowledgebase.ts
      informal.ts
      aggregate.ts
  hosts/
    pi/
      index.ts
      extension.ts
tests/
  toolkit/
    runtime/
    output/
    server/
    knowledgebase/
    informal/
    tools/
    hosts/
```

This is intentionally pragmatic rather than maximally granular.
It gives the rewrite clear homes for the major toolkit responsibilities without over-fragmenting the first implementation.

## Module-group responsibilities

## `src/index.ts`

This should be the curated public root for the reusable toolkit package surface.
It should re-export the stable things that ordinary consumers should rely on, such as:

- client/toolkit factory entrypoints
- stable option/result/error types
- selected host-agnostic helpers that are intentionally public

It should not re-export every internal module blindly.

## `src/toolkit/runtime/`

This should contain shared operational foundations, such as:

- toolkit-wide options/config normalization
- project-root discovery
- executable resolution helpers
- shared error classes
- child-process utilities
- one-shot CLI execution helpers

This directory should sit at or near the bottom of the TypeScript dependency graph.
It should not depend on tool-family modules or host adapters.

## `src/toolkit/output/`

This should contain shared result/output shaping helpers, such as:

- normalized result value types
- truncation helpers
- human-text rendering helpers
- shared error-to-result formatting utilities

This directory should be reusable by all tool families.
It should not depend on host adapters.

## `src/toolkit/server/`

This should contain the TypeScript mirror of the rewrite server protocol and the managed server client.
It should own:

- protocol types used by TypeScript code
- JSON-RPC request/response helpers
- the managed `aftk_server` client

It should depend on runtime helpers, but it should not depend on `pi` or on higher-level tool-definition modules.

## `src/toolkit/knowledgebase/`

This should contain the reusable TypeScript bridge to:

```text
lake exe aftk knowledgebase ...
```

It should own:

- command construction for the knowledge-base CLI surface
- JSON parsing and low-level result handling
- typed wrappers over selected knowledge-base operations

It should depend on runtime helpers and possibly shared output/result types only where appropriate.
It should not depend on host adapters.

## `src/toolkit/informal/`

This should contain the reusable TypeScript bridge to:

```text
lake exe aftk informal ...
```

It should own:

- command construction for the informal CLI surface
- JSON parsing and low-level result handling
- typed wrappers over selected informal operations

It should depend on runtime helpers and possibly shared output/result types only where appropriate.
It should not depend on host adapters.

## `src/toolkit/tools/`

This should contain the agent-facing tool-family factories built on the lower-level clients.
The initial families should include:

- Lean-facing tools built on the managed server client
- knowledge-base tools built on the knowledge-base CLI bridge
- informal tools built on the informal CLI bridge
- an optional aggregate toolset builder that combines selected families for one host session

This directory is where:

- parameter schemas,
- tool descriptions,
- tool execution wrappers,
- and concise human-facing renderings

should live.

It should depend on:

- `src/toolkit/runtime/`
- `src/toolkit/output/`
- `src/toolkit/server/`
- `src/toolkit/knowledgebase/`
- `src/toolkit/informal/`

but not on host adapters.

## `src/hosts/pi/`

This should contain the `pi`-specific mounting layer.
It should remain thin and own only things such as:

- registering toolkit tools into `pi`
- hooking session-shutdown cleanup
- optional explicit stop commands
- small adapter glue to the `@mariozechner/pi-coding-agent` host APIs

It should import from the reusable toolkit code.
The reusable toolkit code should not import from `src/hosts/pi/`.

## `tests/toolkit/`

This should contain TypeScript-side toolkit tests.
A practical split is:

- `tests/toolkit/runtime/` for pure/shared operational helpers
- `tests/toolkit/output/` for truncation/result-shaping tests
- `tests/toolkit/server/` for managed hub and protocol-client tests
- `tests/toolkit/knowledgebase/` for knowledge-base CLI bridge tests
- `tests/toolkit/informal/` for informal CLI bridge tests
- `tests/toolkit/tools/` for tool-family behavior tests
- `tests/toolkit/hosts/` for adapter lifecycle tests where practical

This tree may reuse the existing repository fixture roots under `tests/server/`, `tests/knowledgebase/`, and `tests/informal/` when that reduces duplication.
But the TypeScript test code itself should live under `tests/toolkit/`.

## Dependency direction

The intended dependency shape for the toolkit package is:

```text
src/toolkit/runtime      src/toolkit/output
        ↓                       ↓
src/toolkit/server   src/toolkit/knowledgebase   src/toolkit/informal
              ↘              ↓                ↙
                  src/toolkit/tools
                          ↓
                     src/hosts/pi
```

A more precise reading is:

- `runtime/` should be foundational
- `output/` should also be a shared reusable layer rather than living inside any one tool family
- `server/`, `knowledgebase/`, and `informal/` should sit above runtime
- `tools/` should depend on the lower-level clients and on shared output helpers
- `hosts/pi/` should depend on tool factories, never the other way around

The exact import graph may not be perfectly linear in code, but the design intent is clear:

- host adapters are outermost
- tool-family code sits above lower-level clients
- lower-level clients sit above shared runtime helpers

## Public export policy

The package should adopt a curated export policy.

### Root library export

The main package root should export the stable reusable toolkit surface from:

```text
src/index.ts
```

That surface should likely include:

- selected client constructors/factories
- selected toolset builders
- selected public types and public error classes

### Adapter subpath export

If the package wants a typed host-adapter import surface, it should expose a curated subpath such as:

```text
./pi
```

mapping to:

```text
src/hosts/pi/index.ts
```

This gives custom SDK users a supported import path without making them import arbitrary internal files.

### Extension entrypoint path

The package may also expose a dedicated extension entrypoint path such as:

```text
./pi-extension
```

or simply rely on the file path referenced from the package’s `pi` metadata.

The important point is that the extension entrypoint should stay thin and separate from the library root.

### No deep-import compatibility promise

Imports like these should **not** be treated as stable public API:

```text
src/toolkit/runtime/subprocess.ts
src/toolkit/server/client.ts
src/toolkit/tools/lean.ts
```

Internal refactors should be free to move those files as long as the curated public exports remain stable.

## Package configuration implications

This layout implies several high-level package-configuration changes.

### `package.json`

The package should stop signaling a Bun-scaffold-only layout.
At minimum, the package configuration should move toward:

- a curated package entrypoint strategy, preferably via explicit exports
- a `pi` extension path that points at the thin adapter entrypoint rather than at the toolkit core
- dependencies and dev-dependencies that reflect the chosen Node-compatible runtime assumptions

A plausible end state is conceptually:

```json
{
  "type": "module",
  "exports": {
    ".": "./src/index.ts",
    "./pi": "./src/hosts/pi/index.ts",
    "./pi-extension": "./src/hosts/pi/extension.ts"
  },
  "pi": {
    "extensions": ["./src/hosts/pi/extension.ts"]
  }
}
```

The exact package metadata can be finalized during implementation, but the layout should be built to support this style.

### `tsconfig.json`

The TypeScript config should likewise stop reflecting a Bun playground scaffold.
At a layout level, it should include the real toolkit source and toolkit test trees, something conceptually like:

- `src/**/*.ts`
- `tests/toolkit/**/*.ts`

It should also stop implying that root-level `index.ts` is the main architecture of the package.

The deeper runtime/compiler details belong in `plans/toolkit/runtime.md`, but the source-tree shape should already be reflected in the config.

## Root-file migration policy

The rewrite currently has:

- root `index.ts`
- Bun-oriented `package.json`
- Bun-oriented `tsconfig.json`

That is useful only as scaffolding.
It should not be allowed to harden into the toolkit architecture by accident.

So the implementation should explicitly perform this migration:

1. create the `src/` tree
2. create `src/index.ts` as the curated library root
3. move real toolkit code under `src/toolkit/` and `src/hosts/`
4. update package metadata and TS config accordingly
5. delete the root placeholder `index.ts` or reduce it to a temporary re-export shim

## Boundaries and anti-patterns

The layout should explicitly avoid the following anti-patterns.

### 1. No new `lambda/src` home in the rewrite

The rewrite toolkit is not just a pi extension.
Using `lambda/src` again would blur the library/adapter boundary from the beginning.

### 2. No single giant `aftk-tools.ts` replacement file

Even if the first implementation is modest, it should still preserve distinct homes for:

- runtime/process helpers
- server client logic
- CLI bridges
- output shaping
- tool families
- host adapters

### 3. No host-specific imports from the toolkit core

Modules under `src/toolkit/` should not import from `@mariozechner/pi-coding-agent` directly unless a later doc gives an exceptional reason.
That dependency belongs in `src/hosts/pi/`.

### 4. No public API by accidental filesystem exposure

Internal file paths should not become the compatibility story.
The compatibility story should be curated exports.

### 5. No mixing TypeScript test code into Lean test namespaces

The rewrite already has coherent Lean test trees.
Toolkit tests should be adjacent to them, not mixed into `AFTKTest/*`.

## Initial implementation checklist for this layout

Before the toolkit implementation can sensibly proceed, the repository should reach at least this structural baseline:

- `plans/toolkit/layout.md` exists and is accepted as the layout reference
- `plans/toolkit/` exists as the component-plan directory for this layer
- `src/` exists and contains a real toolkit library root
- `src/toolkit/` exists with the main module groups defined in this document
- `src/hosts/pi/` exists for thin host adapters
- `tests/toolkit/` exists for TypeScript-side toolkit tests
- `package.json` and `tsconfig.json` have been updated to reflect the real source tree
- the root placeholder `index.ts` is no longer the owner of toolkit implementation logic

## Summary

The rewrite toolkit should be laid out as a **single TypeScript package with multiple curated entrypoints**.
Its implementation should live under a real `src/` tree, with a visible split between:

- reusable toolkit core code under `src/toolkit/`
- and thin host adapters under `src/hosts/`

Within the toolkit core, the layout should distinguish:

- shared runtime/process helpers,
- shared output/result helpers,
- the managed server client,
- the knowledge-base CLI bridge,
- the informal CLI bridge,
- and the tool-family factories built on top of them.

This preserves the best architectural idea from the main worktree — thin adapter over shared toolkit logic — while avoiding the one-large-file layout and broadening the toolkit into a true library for the rewrite’s multi-layer architecture.
