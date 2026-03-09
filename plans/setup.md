# AFTK setup script plan

## Status

This file now serves as a design/status note for the implemented `aftk_setup` Lake script.
The current implementation is documented in `docs/aftk_setup.md`; the research sections below are preserved mainly as rationale for the choices now reflected in `lakefile.lean`.

## Implementation status

- Overall status: Implemented
- Implemented in code: Yes
- Last updated basis: the current setup-script implementation in `lakefile.lean`, the pi host-adapter code in `src/hosts/pi/**`, `package.json`, and `docs/aftk_setup.md`
- Main deferred follow-ons: optional flags such as `--check` or `--force`, any future package-distribution hardening, and any broader setup tasks beyond the current `.pi/` resources

The current repository already supports:

- `lake run aftk_setup` inside `aftk` itself
- `lake run aftk_setup` inside a Lake workspace that depends on `aftk`
- generation of `.pi/extensions/aftk-toolkit.ts`
- generation of `.pi/APPEND_SYSTEM.md`
- conservative overwrite behavior for script-managed files

## Historical note

The research sections below were written before the setup script was implemented.
Where they discuss migration from `lakefile.toml`, missing setup support, or design alternatives, treat them as historical context only.
Current behavior is documented in `docs/aftk_setup.md` and implemented in `lakefile.lean`.

## Goal

Add a Lake script whose first jobs are to set up the AFTK pi extension locally for the current Lake workspace and to install a project-local appended system prompt for AFTK-aware agent behavior.

For v1, “setup” should mean:

- discover the current workspace root,
- discover the filesystem location of the `aftk` package within that workspace,
- create a project-local pi extension shim under `.pi/extensions/`,
- create a project-local appended system prompt at `.pi/APPEND_SYSTEM.md`, and
- make the shim re-export AFTK’s pi extension entrypoint from the discovered package location while the appended prompt gives agents concise AFTK-specific autoformalization guidance.

The important constraint is that this must work both when `aftk` is the root package and when `aftk` is only a dependency.

## Research basis

### AFTK files studied

- `lakefile.toml`
- `package.json`
- `README.md`
- `docs/architecture.md`
- `docs/informal/overview.md`
- `docs/informal/cli.md`
- `docs/server/overview.md`
- `.pi/extensions/aftk-toolkit.ts`
- `src/index.ts`
- `src/hosts/pi/extension.ts`
- `src/hosts/pi/index.ts`
- `src/toolkit/tools/aggregate.ts`
- `src/toolkit/runtime/options.ts`
- `src/toolkit/runtime/project-root.ts`
- `src/toolkit/runtime/executables.ts`

### Main-worktree workflow docs studied

- `../aftk/docs/agent-playbook.md`
- `../aftk/docs/future/autoformalization-tools.md`

### Lake / Lean source files studied

From the Lean 4.28.0 toolchain source at:
`/home/dev/.elan/toolchains/leanprover--lean4---v4.28.0/src/lean/lake/`

- `README.md`
- `Lake/CLI/Main.lean`
- `Lake/CLI/Help.lean`
- `Lake/CLI/Build.lean`
- `Lake/Config/Script.lean`
- `Lake/Config/Monad.lean`
- `Lake/Config/Workspace.lean`
- `Lake/Config/Package.lean`
- `Lake/Load/Package.lean`
- `Lake/Load/Lean/Eval.lean`
- `Lake/Load/Config.lean`
- `Lake/Load/Materialize.lean`
- `Lake/Util/FilePath.lean`
- `Lake/DSL/Syntax.lean`
- `Lake/DSL/Script.lean`

### pi docs studied

From:
`/home/dev/.nvm/versions/node/v25.5.0/lib/node_modules/@mariozechner/pi-coding-agent/`

- `README.md`
- `docs/extensions.md`
- `docs/packages.md`
- `docs/settings.md`
- `docs/skills.md`
- `examples/extensions/README.md`
- `examples/sdk/03-custom-prompt.ts`

## Key research findings

## 1. Lake scripts require a Lean config file

Lake scripts are defined with the Lean `script` DSL, not in TOML.
The relevant docs and code are:

- `lake/README.md` (“Writing and Running Scripts”)
- `Lake/DSL/Syntax.lean`
- `Lake/DSL/Script.lean`
- `Lake/Config/Script.lean`

So if we want an `aftk_setup` script, `aftk` needs a `lakefile.lean`.

## 2. `lakefile.lean` takes precedence over `lakefile.toml`

`Lake/Load/Package.lean` shows that when both `lakefile.lean` and `lakefile.toml` are present, Lake chooses the Lean file.

That means there are really only two sane options:

1. migrate `aftk` to a real `lakefile.lean`, or
2. keep `lakefile.toml` around as dead backup text while the Lean file becomes authoritative.

Maintaining both as live sources of truth would be error-prone.

I also used `lake translate-config lean` on the current `lakefile.toml`, and the generated Lean config is already very close to what we need:

```lean
import Lake
open System Lake DSL

package aftk where
  testDriver := "aftk_test"
  version := v!"0.1.0"

require lean_worker from git "https://github.com/adamtopaz/lean_worker"@"main"

lean_lib AFTK
lean_lib AFTKTest

@[default_target] lean_exe aftk where
  root := `Main
  supportInterpreter := true

lean_exe aftk_server where
  root := `AFTK.Server.Main
  supportInterpreter := true

-- etc.
```

So the migration cost is low.

## 3. `lake run` is just `lake script run`, and it can find dependency scripts

`Lake/CLI/Help.lean` documents:

- `lake run` is an alias for `lake script run`
- script syntax is `[[<package>/]<script>]`

`Lake/CLI/Main.lean` shows that unqualified script lookup goes through `Workspace.findScript?`, and `Lake/Config/Workspace.lean` shows that `findScript?` searches all workspace packages, not just the root.

This is the key enabler for the desired UX:

- if a workspace depends on `aftk`, then `lake run aftk_setup` can resolve the dependency’s script,
- provided the root package does not define another script with the same name.

Because `aftk_setup` is fairly specific, this is a reasonable v1 assumption.

### Empirical check

I verified this with two temporary test workspaces:

- a Lean-configured root depending on a package `dep` that defined a script and executable,
- a TOML-configured root depending on the same Lean-configured `dep`.

Observed behavior:

- `lake run dep_hello` worked from the dependent workspace,
- `lake run dep/dep_hello ...` also worked,
- `lake exe depbin` also worked unqualified from the dependent workspace,
- and this held even when the root workspace itself used `lakefile.toml`.

So dependency scripts and executables are genuinely visible from the workspace-level CLI.

## 4. A script can inspect the loaded workspace directly

`Lake/Config/Script.lean` defines script functions in `ScriptM := LakeT IO`.
`Lake/Config/Monad.lean` exposes helpers like:

- `getWorkspace`
- `getRootPackage`
- `findPackageByName?`

This means `aftk_setup` can do its discovery entirely inside Lake, with no shell parsing and no guessing about `.lake/packages` layout.

This is exactly the right place to do the setup, because Lake already knows the resolved workspace after path dependencies, git dependencies, and manifest resolution.

## 5. Use `Package.dir`, not `Package.relDir`, to locate the package on disk

`Lake/Config/Package.lean` gives each package both:

- `dir` — absolute package directory
- `relDir` — directory “relative to the workspace”

But `Lake/Load/Materialize.lean` makes an important subtlety visible for path dependencies:
path dependencies preserve the given path source, and that can be absolute.

I confirmed this experimentally:
for a path dependency, `pkg.dir` was the absolute path to the dependency, and `pkg.relDir` was also absolute.

So for setup purposes:

- `pkg.dir` is the reliable locator,
- `pkg.relDir` should not be used to build the target extension path.

## 6. The current AFTK pi extension already exposes the relevant tool families, and it still looks compatible with dependency use

The current pi extension entrypoint is:

- `src/hosts/pi/extension.ts`

and the current local shim is:

- `.pi/extensions/aftk-toolkit.ts`

with content:

```ts
export { default } from "../../src/hosts/pi/extension.ts";
```

The extension entrypoint calls:

```ts
registerToolkitExtension(pi, { cwd: process.cwd() })
```

`src/hosts/pi/index.ts` and `src/toolkit/tools/aggregate.ts` show that this registers the aggregate AFTK toolkit, which currently includes:

- Lean/server tools,
- knowledge-base tools, and
- informal tools.

That matters for the setup-generated appended system prompt:
it should describe the full AFTK surface available to agents in an autoformalization project, not only the old Lean hub methods.

The runtime then:

- resolves the current Lean project root upward from that cwd,
- and defaults to launching:
  - `lake exe aftk_server`
  - `lake exe aftk knowledgebase`
  - `lake exe aftk informal`

The Lake source shows that executable lookup also searches the full workspace, not only the root package.
My temporary experiment with `lake exe depbin` confirmed this.

So the current extension runtime likely does **not** need a separate “dependency mode” just to make executable lookup work.
The setup script mainly needs to make pi load the right extension source file and install the right static agent guidance.

## 7. Project-local pi extensions should go in `.pi/extensions/`

The pi docs (`docs/extensions.md`) say project-local extensions are auto-discovered from:

- `.pi/extensions/*.ts`
- `.pi/extensions/*/index.ts`

They are also hot-reloadable via `/reload` when discovered this way.

This is a better fit than editing `.pi/settings.json` because:

- it matches pi’s documented local-extension workflow,
- it avoids JSON merge/update logic,
- it matches the current structure already used inside this repository,
- and a single generated shim file is enough.

## 8. pi also supports a project-local appended system prompt via `.pi/APPEND_SYSTEM.md`

The pi README documents that project-local `.pi/SYSTEM.md` replaces the default system prompt, while `APPEND_SYSTEM.md` appends to it without replacing it.
`examples/sdk/03-custom-prompt.ts` also confirms that `APPEND_SYSTEM.md` is part of the default loader behavior.

For this setup script, `.pi/APPEND_SYSTEM.md` is the right mechanism because:

- it is documented project-local behavior,
- it layers AFTK instructions on top of pi’s official prompt instead of replacing it,
- it does not require custom extension code just to inject static instructions,
- and it can be picked up on startup or via `/reload`.

This is a better fit than encoding the instructions inside the extension implementation or requiring users to pass manual `--append-system-prompt` flags.

## 9. pi can load TypeScript source directly; no build step is required

The pi extension docs say extensions are loaded via `jiti`, so TypeScript source can be loaded directly.

That means the generated shim can point straight at:

- `src/hosts/pi/extension.ts`

There is no need for a separate compiled JS artifact for this first version.

## 10. Directly importing the source file is viable today because the current runtime code is self-contained

I searched the current `src/**/*.ts` imports.
At the moment, the runtime path used by the pi extension only depends on:

- local source files, and
- Node built-ins (`node:*`).

I did **not** find runtime imports from third-party npm packages in the current toolkit source.
That matters because a Lake dependency living under `.lake/packages/aftk` will not have had `npm install` run by Lake.

So the current “generated shim points directly into the AFTK source tree” design is viable **today**.

Caveat:
if the pi extension later gains real third-party runtime npm dependencies, this setup strategy will need to be revisited.
At that point we may need either:

- a bundled JS artifact in the repo, or
- a separate pi-package installation path.

## 11. Lake’s existing `relPathFrom` helper is not enough for a fully portable relative import path

`Lake/Util/FilePath.lean` defines `relPathFrom`, but it is only a prefix-strip helper:

- if `path` is under `root`, it returns the suffix,
- otherwise it returns the original path unchanged.

That is not enough to compute a true relative module specifier between arbitrary paths, such as:

- project root → sibling checkout path dependency
- `.pi/extensions/aftk-toolkit.ts` → `../../.lake/packages/aftk/...`

So if we want the generated shim to use a relative import specifier, we should plan on a small custom helper for relative-path computation.

## Recommended design

## 1. Make `lakefile.lean` the authoritative config

Recommendation:

- create `lakefile.lean` from the translated current TOML config,
- add the `aftk_setup` script there,
- and treat the Lean config as the single source of truth.

I do **not** recommend long-term dual maintenance of `lakefile.toml` and `lakefile.lean`.
Keeping the TOML file temporarily during migration is acceptable, but once the Lean file is added, it is the one Lake will actually use.

## 2. Define a non-default script named `aftk_setup`

The script should be explicitly invoked as:

- `lake run aftk_setup`

and should **not** be the default script for bare `lake run`.

This keeps the setup action explicit and avoids surprising behavior.

## 3. Write the pi setup artifacts into the current workspace root, not the AFTK package root

The script should treat the current Lake workspace as “the project being set up”.
That means the destinations should be based on:

- `ws.dir` or `ws.root.dir`

not on `IO.currentDir`, and not on `aftkPkg.dir`.

In particular, the script should write:

- `.pi/extensions/aftk-toolkit.ts`
- `.pi/APPEND_SYSTEM.md`

That way:

- in `aftk` itself, both files land in `aftk/.pi/...`
- in a dependent project, both files land in `that-project/.pi/...`

which is exactly what pi expects for project-local resources.

## 4. Discover the AFTK package through the workspace

The script should do roughly this logically:

1. `let ws ← getWorkspace`
2. `let projectDir := ws.dir`
3. `let some aftkPkg := ws.findPackageByName? `aftk``
4. `let entryFile := aftkPkg.dir / "src" / "hosts" / "pi" / "extension.ts"`
5. verify `entryFile` exists
6. generate the shim file under `projectDir / ".pi" / "extensions" / "aftk-toolkit.ts"`
7. generate the appended prompt under `projectDir / ".pi" / "APPEND_SYSTEM.md"`

This is better than hardcoding `.lake/packages/aftk/...` because:

- path dependencies may live elsewhere,
- future source kinds may materialize differently,
- and Lake already knows the truth.

## 5. Generate a simple shim file, matching the current project pattern

The generated file should stay minimal.
Something in this shape:

```ts
// Generated by `lake run aftk_setup`. Re-run to refresh.
export { default } from "../../src/hosts/pi/extension.ts";
```

In a dependent project with a git/Reservoir-style materialized dependency, the import would more likely look like:

```ts
export { default } from "../../.lake/packages/aftk/src/hosts/pi/extension.ts";
```

The exact specifier should be generated from the discovered package directory.

## 6. Generate a project-local appended system prompt at `.pi/APPEND_SYSTEM.md`

Recommendation:

- create `.pi/APPEND_SYSTEM.md` beside the extension shim,
- use pi’s documented append-to-default mechanism rather than replacing the system prompt,
- and include a clear generated-file header marker.

The generated prompt should explain at least three things.

### a. What the setup enables

It should tell the model that this project now has AFTK toolkit access, including:

- Lean/server tools for opening Lean files, querying hover/goals/infoview, and exploring tactics,
- knowledge-base tools for listing, showing, searching, validating, and relating knowledge-base nodes,
- informal tools for inspecting tracked declarations/references/dependencies and rendering knowledge-base-backed presentation.

### b. The general AFTK autoformalization loop

It should give a concise workflow such as:

1. inspect the current Lean and informal context rather than guessing,
2. use knowledge-base and informal tools to understand the target node, related notes, and tracked declarations,
3. use Lean/server tools to inspect the formal goal state,
4. use tactic exploration tools to try branches transiently,
5. turn a successful branch into real Lean source edits,
6. re-check the file and continue iteratively.

### c. The key safety / architecture rules

It should remind agents that:

- tactic exploration results are transient search state, not persisted proof edits,
- canonical prose and metadata live in the knowledge base,
- the informal layer is the Lean-facing bridge to that knowledge,
- and agents should prefer inspecting actual AFTK state through tools instead of inventing assumptions.

Because `.pi/APPEND_SYSTEM.md` is appended on every turn, the content should stay concise and durable.
If the workflow guidance grows much longer, that is a good sign that a future `.pi/skills/` skill or prompt template may be a better home for the full long-form playbook.

## 7. Prefer a relative import specifier, with fallback if necessary

Recommendation for the specifier generation policy:

- prefer a relative import specifier from the generated shim file to the discovered `entryFile`,
- normalize separators to `/`,
- fall back only if a relative specifier is impossible or awkward on the current platform.

Why prefer relative:

- it matches the current repository’s own local shim,
- it is more portable across workspace moves,
- and it avoids baking machine-specific absolute paths into the generated file.

Because Lake does not already expose a general relative-path helper for this, we should plan on a tiny custom helper for v1.

## 8. Make the script idempotent and cautious about overwrites

The script should be safe to rerun.
Recommended behavior for each generated file is:

- if the destination file does not exist: create it
- if it exists with exactly the desired content: print a no-op success message
- if it exists and contains a recognizable generated header marker: overwrite it
- otherwise: fail with a clear message instead of clobbering a user-owned file

This is especially important because both `.pi/extensions/` and `.pi/APPEND_SYSTEM.md` are user-editable.

## 9. Keep v1 scope narrow

For the first version, the script should only:

- create/update the shim file
- create/update `.pi/APPEND_SYSTEM.md`
- create parent directories as needed
- print a clear success/failure summary

It should **not** yet:

- modify `.pi/settings.json`
- try to launch pi
- try to reload an already-running pi session
- install npm packages
- inject dynamic prompt text through extension hooks
- rewrite toolkit runtime executable specs
- handle broader future setup tasks

## Proposed implementation outline

## Phase 1: configuration migration

1. Translate `lakefile.toml` into `lakefile.lean`.
2. Check that all existing libs/executables/test-driver settings are preserved.
3. Decide whether to remove `lakefile.toml` immediately or keep it temporarily with the explicit understanding that it is no longer authoritative.

## Phase 2: script addition

1. Add `script aftk_setup (args) do ...` to `lakefile.lean`.
2. For v1, reject unexpected positional args with a friendly usage message.
3. Use `getWorkspace` to locate:
   - the current workspace root
   - the `aftk` package
   - the extension entry file
   - the two output paths under `.pi/`

## Phase 3: pi resource generation

1. Create `.pi/` and `.pi/extensions/` under the current workspace root.
2. Compute the module specifier to AFTK’s `src/hosts/pi/extension.ts`.
3. Write `.pi/extensions/aftk-toolkit.ts`.
4. Write `.pi/APPEND_SYSTEM.md` with concise AFTK autoformalization instructions.
5. Include generated-file header markers in both files.
6. Print what was discovered and what was written.

## Phase 4: polish

1. Make reruns no-op when already up to date.
2. Provide clear messages like:
   - “AFTK pi extension installed at …”
   - “AFTK appended system prompt installed at …”
   - “If pi is already running, use `/reload`.”
3. Add friendly diagnostics for:
   - `aftk` package not found in workspace
   - expected extension entry file missing
   - existing destination file not generated by us

## Validation checklist for the later implementation

After implementation, I would validate at least these cases:

### Case A: inside `aftk` itself

- run `lake run aftk_setup`
- verify `.pi/extensions/aftk-toolkit.ts` exists
- verify it points at the local `src/hosts/pi/extension.ts`
- verify `.pi/APPEND_SYSTEM.md` exists
- verify it contains concise AFTK tool/workflow guidance
- rerun and confirm idempotent behavior

### Case B: inside a dependent project with a path dependency on `aftk`

- run `lake run aftk_setup`
- verify the shim lands in the dependent project’s `.pi/extensions/`
- verify it points at the dependency package location returned by Lake
- verify `.pi/APPEND_SYSTEM.md` lands in the dependent project root
- verify pi can load the extension and appended prompt from the dependent project

### Case C: inside a dependent project with a materialized dependency under `.lake/packages/`

- run `lake run aftk_setup`
- verify the shim points into `.lake/packages/aftk/...`
- verify `.pi/APPEND_SYSTEM.md` is still created in the dependent project
- confirm the extension still uses the dependent project as its runtime cwd/project root

### Case D: overwrite safety

- place a hand-written `.pi/extensions/aftk-toolkit.ts`
- place a hand-written `.pi/APPEND_SYSTEM.md`
- verify the script refuses to overwrite either one unless it recognizes its own generated marker

### Case E: prompt pickup

- start pi in the configured project, or run `/reload` if it is already running
- confirm the effective system prompt includes the appended AFTK instructions
- confirm the extension tools are available in the same session

## Open questions / likely follow-up work

## 1. Should we also harden executable lookup by qualifying targets?

The current evidence suggests unqualified lookup already works for dependency executables.
Still, a future hardening step could make the toolkit runtime explicitly use:

- `lake exe aftk/aftk_server`
- `lake exe aftk/aftk`

when appropriate, to avoid possible name collisions with root-package executables.
I do not think this is required for the initial setup script.

## 2. Should the setup script derive the pi entrypoint from `package.json`?

Today, hardcoding:

- `src/hosts/pi/extension.ts`

is acceptable and simple.
A future refinement could parse `package.json` and read the `pi.extensions` entry, but that is not necessary for the first version.

## 3. Should the long-form autoformalization guidance eventually become a pi skill?

Probably not for v1.
The first generated `.pi/APPEND_SYSTEM.md` should stay concise and always-on.

But pi skills are a better fit for large, on-demand workflow documents because only their descriptions stay in the always-loaded prompt and the full skill content is loaded on demand.
So if the AFTK playbook grows substantially, a future `.pi/skills/` resource may be better than continually expanding `APPEND_SYSTEM.md`.

## 4. Should we add flags like `--force` or `--check`?

Probably not for v1.
A zero-argument, idempotent setup command is enough to get started.
If the script becomes more central later, useful flags would be:

- `--force`
- `--check`
- `--print-paths`

## Final recommendation

The cleanest plan is:

1. migrate `aftk` to `lakefile.lean`,
2. add a named `script aftk_setup`,
3. have the script use Lake’s workspace object to find the `aftk` package and its absolute `pkg.dir`,
4. generate a project-local pi shim under `.pi/extensions/aftk-toolkit.ts`,
5. generate a project-local appended system prompt at `.pi/APPEND_SYSTEM.md`,
6. make the shim re-export AFTK’s pi extension entrypoint using a generated relative import path when possible,
7. keep the prompt concise, focused on the available AFTK tool families and the general autoformalization loop,
8. keep the script idempotent and conservative about overwriting existing files.

This approach is fully aligned with Lake’s actual workspace model, with pi’s documented local resource-loading model, and with the current structure of the AFTK TypeScript extension code and autoformalization workflow.
