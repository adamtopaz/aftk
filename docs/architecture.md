# Implemented architecture

This document describes the current implementation state of the `aftk` codebase.
It is intentionally implementation-facing: it focuses on what is in code now, which files own which responsibilities, and where the current boundaries are.

## Current status

The architecture is organized into five layers:

1. Knowledge base
2. Informal
3. Server / file worker
4. Toolkit
5. AI autoformalization agents

Today, the first four layers are implemented.
The fifth layer — AI-agent orchestration — is still future work.

For the current roadmap, see `plan.md`.
For detailed layer-by-layer design notes, see `plans/README.md`.

## Layer summary

| Layer | Current status | Main entrypoints | Main code roots |
| --- | --- | --- | --- |
| Knowledge base | Implemented | `lake exe aftk knowledgebase ...`, `import AFTK.KnowledgeBase` | `AFTK/KnowledgeBase*.lean`, `AFTK/KnowledgeBase/**` |
| Informal | Implemented | `lake exe aftk informal ...`, `import AFTK.Informal` | `AFTK/Informal*.lean`, `AFTK/Informal/**` |
| Server / file worker | Implemented | `lake exe aftk_server`, `lake exe aftk_file_worker <path>`, `import AFTK.Server`, `import AFTK.FileWorker` | `AFTK/Server*.lean`, `AFTK/Server/**`, `AFTK/FileWorker*.lean`, `AFTK/FileWorker/**` |
| Toolkit | Implemented | `src/index.ts`, package exports `./pi` and `./pi-extension`, `lake run aftk_setup` | `src/index.ts`, `src/toolkit/**`, `src/hosts/pi/**`, `tests/toolkit/**`, `package.json`, `lakefile.lean` |
| AI agents | Not implemented | none yet | no agent-layer orchestration code yet |

## High-level dependency shape

The implemented stack is layered the way the top-level plan intends:

```text
AFTK.KnowledgeBase
        ↓
AFTK.Informal
        ↓
AFTK.Server / AFTK.FileWorker
        ↓
TypeScript toolkit (`src/toolkit/**`, `src/hosts/pi/**`)
```

More concretely:

- `AFTK.KnowledgeBase` owns canonical natural-language storage and filesystem semantics.
- `AFTK.Informal` resolves `informal[...]` references through the knowledge base and tracks which Lean declarations use them.
- `AFTK.Server` and `AFTK.FileWorker` expose a long-running JSON-RPC service for Lean queries and tactic exploration, and reuse the informal layer for richer hover at `informal[...]` sites.
- the toolkit layer packages those lower-layer services into reusable TypeScript clients, normalized tool results, agent-facing tool families, and thin pi integration helpers.

## Layer-to-component index

This section gives the shortest implementation map from layer to concrete components.
Use it as the top-level navigation guide into the codebase.

### 1. Knowledge base layer

Main docs:

- `docs/knowledgebase/overview.md`
- `docs/knowledgebase/library.md`
- `docs/knowledgebase/storage.md`
- `docs/knowledgebase/cli.md`

Main code components:

| Component | Code | Role |
| --- | --- | --- |
| Public root | `AFTK/KnowledgeBase.lean` | Re-exports reusable knowledge-base modules |
| Types | `AFTK/KnowledgeBase/Types.lean` | Node ids, metadata, manifest, errors, JSON instances |
| Path layout | `AFTK/KnowledgeBase/PathLayout.lean` | Canonical root/path mapping |
| Serialization | `AFTK/KnowledgeBase/Serialization.lean` | Strict parsing and canonical rendering |
| Storage | `AFTK/KnowledgeBase/Storage.lean` | Real filesystem operations |
| Validation | `AFTK/KnowledgeBase/Validation.lean` | Structured validation reports |
| Search | `AFTK/KnowledgeBase/Search.lean` | Direct-scan search and relationship queries |
| CLI | `AFTK/KnowledgeBase/Cli/*` | Parsing, dispatch, rendering, help |

### 2. Informal layer

Main docs:

- `docs/informal/overview.md`
- `docs/informal/library.md`
- `docs/informal/cli.md`

Main code components:

| Component | Code | Role |
| --- | --- | --- |
| Public root | `AFTK/Informal.lean` | Re-exports reusable informal modules |
| Syntax | `AFTK/Informal/Syntax.lean` | `informal[...]` syntax |
| Placeholder | `AFTK/Informal/Placeholder.lean` | Unsound placeholder primitive |
| Options | `AFTK/Informal/Options.lean` | `aftk.informal.root` option |
| References | `AFTK/Informal/References.lean` | Reference validation and KB-backed resolution |
| Tracking | `AFTK/Informal/Tracking.lean` | Persistent declaration→reference tracking |
| Dependencies | `AFTK/Informal/Dependencies.lean` | Derived dependency views |
| Presentation | `AFTK/Informal/Presentation.lean` | Compact/rich rendering |
| Elaborator | `AFTK/Informal/Elaborator.lean` | Actual term elaboration behavior |
| CLI | `AFTK/Informal/Cli/*` | Parsing, environment import, rendering |

### 3. Server / file-worker layer

Main docs:

- `docs/server/overview.md`
- `docs/server/library.md`
- `docs/server/protocol.md`

Main code components:

| Component | Code | Role |
| --- | --- | --- |
| Hub public root | `AFTK/Server.lean` | Re-exports hub-side modules |
| Worker public root | `AFTK/FileWorker.lean` | Re-exports worker-side modules |
| Protocol | `AFTK/Server/Protocol.lean` | Shared JSON-RPC types and error helpers |
| Transport | `AFTK/Server/Transport.lean` | StdIO transport and child-process helpers |
| Hub | `AFTK/Server/Hub.lean` | Sessions, spawning, forwarding, invalidation |
| Hub main | `AFTK/Server/Main.lean` | `aftk_server` executable bootstrap |
| Worker context | `AFTK/FileWorker/Context.lean` | One-shot Lean snapshot |
| Worker queries | `AFTK/FileWorker/Queries.lean` | Hover/goals/infoview queries |
| Worker tactic state | `AFTK/FileWorker/TacticState.lean` | Transient goal-state nodes and tactic execution |
| Worker informal integration | `AFTK/FileWorker/Informal.lean` | Rich `informal[...]` hover |
| Worker handlers | `AFTK/FileWorker/Handlers.lean` | Worker RPC method table |
| Worker main | `AFTK/FileWorker/Main.lean` | `aftk_file_worker` executable bootstrap |

### 4. Toolkit layer

Main docs:

- `docs/toolkit/overview.md`
- `docs/toolkit/library.md`
- `docs/toolkit/testing.md`
- `docs/aftk_setup.md`

Main code components:

| Component | Code | Role |
| --- | --- | --- |
| Public package root | `src/index.ts` | Curated TypeScript export surface |
| Compatibility shim | `index.ts` | Transitional re-export of `src/index.ts` |
| Runtime | `src/toolkit/runtime/*` | Project-root discovery, executable resolution, subprocess helpers, runtime errors |
| Output | `src/toolkit/output/*` | Normalized tool results, truncation, diagnostics, shared render helpers |
| Server protocol/client | `src/toolkit/server/*` | TypeScript mirror of the public hub protocol and managed `aftk_server` client |
| Knowledge-base client | `src/toolkit/knowledgebase/client.ts` | JSON CLI bridge for `aftk knowledgebase ...` |
| Informal client | `src/toolkit/informal/client.ts` | JSON CLI bridge for `aftk informal ...` |
| Tool definitions | `src/toolkit/tools/*` | Lean/server-backed, knowledge-base, informal, and aggregate tool families |
| Pi adapters | `src/hosts/pi/*` | Thin direct-SDK and extension-style mounting helpers |
| Setup script | `lakefile.lean` | `aftk_setup` Lake script for project-local pi integration |

### 5. AI-agent layer

Current implementation status:

- not implemented yet
- there is no agent runtime, orchestration layer, or model-facing autoformalization code in the repository today

## What is canonical, and where

### Canonical natural-language data

Canonical prose lives only in the knowledge base:

- Markdown body: `knowledgebase/nodes/**/*.md`
- metadata JSON: `knowledgebase/nodes/**/*.json`
- storage manifest: `knowledgebase/manifest.json`

The informal layer does **not** introduce a second prose store.
The toolkit also does **not** introduce one.
It only wraps the lower-layer public interfaces.

### Derived or transient data

The current implementation has four important kinds of non-canonical state:

1. **Knowledge-base internal directories** under `knowledgebase/.aftk/`
   - reserved for internal/derived data
   - currently created by `init`
   - indexing and repair logic are still deferred
2. **Informal tracking state** inside Lean environments
   - declaration → referenced-node associations
   - imported and merged by a `SimplePersistentEnvExtension`
3. **Worker-local tactic state** in the server layer
   - opaque ids like `node-0`, `node-1`, ...
   - session-local and non-persistent
   - invalidated by worker restart or file reopen
4. **Toolkit runtime state** inside the Node process
   - managed hub child-process ownership
   - pending JSON-RPC requests keyed by numeric ids
   - bounded stdout/stderr capture and diagnostics
   - not persisted across process restart

## Executables, package entrypoints, and user-facing commands

### Unified Lean CLI

The top-level Lean executable is:

```text
lake exe aftk <command> ...
```

It currently dispatches to:

- `knowledgebase`
- `informal`

The dispatch logic lives in `Main.lean`.

### Standalone server executables

The server layer is exposed separately:

```text
lake exe aftk_server
lake exe aftk_file_worker <path>
```

`aftk_server` is the public JSON-RPC hub.
`aftk_file_worker` is the internal per-file worker executable spawned by the hub.

### Toolkit package entrypoints

The TypeScript package exposes these main entrypoints:

- `src/index.ts` via package export `.`
- `src/hosts/pi/index.ts` via package export `./pi`
- `src/hosts/pi/extension.ts` via package export `./pi-extension`

There is no separate standalone toolkit executable.
The toolkit talks to the lower layers through:

- `aftk_server`
- `aftk knowledgebase ...`
- `aftk informal ...`

### Lake setup script

The repository also exposes a Lake script:

```text
lake run aftk_setup
```

This script writes project-local pi integration files under `.pi/`.
See `docs/aftk_setup.md`.

## Top-level code roots

These are the highest-level code files to read first:

- `AFTK.lean` — umbrella Lean import
- `Main.lean` — top-level Lean CLI dispatch to `knowledgebase` and `informal`
- `AFTK/KnowledgeBase.lean` — knowledge-base public root
- `AFTK/Informal.lean` — informal public root
- `AFTK/Server.lean` — server public root
- `AFTK/FileWorker.lean` — file-worker public root
- `AFTK/Server/Main.lean` — hub executable main
- `AFTK/FileWorker/Main.lean` — worker executable main
- `src/index.ts` — toolkit public package root
- `src/hosts/pi/index.ts` — pi mounting helpers
- `src/hosts/pi/extension.ts` — default pi extension entrypoint
- `lakefile.lean` — Lake package config plus `aftk_setup`

## Testing structure

The repository now has two test tracks.

### Lean-layer tests

Run with:

```text
lake test
```

That driver runs three suite executables:

- `aftk_knowledgebase_test`
- `aftk_informal_test`
- `aftk_server_test`

These tests live under `AFTKTest/` and use checked-in fixtures under `tests/`.

### Toolkit tests

Run with:

```text
npm run test:toolkit
```

Or run everything together with:

```text
npm run test:all
```

The toolkit tests live under `tests/toolkit/` and cover:

- runtime helpers
- output truncation
- managed server-client behavior
- Lean/server-backed tool definitions
- knowledge-base CLI-backed tools
- informal CLI-backed tools
- pi adapter registration and cleanup wiring

## Important current limitations

These are deliberate or current implementation boundaries:

- Knowledge-base **repair** and **indexing** are still design-only.
- The informal layer is read/query oriented; it does not mutate knowledge-base content.
- `informal[...]` uses an explicit unsound placeholder axiom for gradual formalization.
- The server uses a **one-shot file snapshot** model.
  It does not support in-memory versioned edits.
- File changes invalidate workers by file stamp and require reopen.
- The toolkit is query/presentation first for the knowledge-base and informal CLIs.
  It does not yet wrap the full mutation/admin surface.
- Toolkit request cancellation is local waiting cancellation only.
  It does not remotely cancel an already-sent hub request.
- The AI autoformalization agent layer is not implemented yet.

## Practical mental model

A good short mental model of the current codebase is:

- the **knowledge base** is the source of truth for prose,
- the **informal layer** turns knowledge-base node ids into Lean placeholders plus trackable declaration metadata,
- the **server layer** exposes Lean/editor-style queries over real files while enriching `informal[...]` hovers through the lower layers,
- and the **toolkit layer** packages those lower-layer services into stable Node- and agent-facing clients, tools, and pi integration helpers.

If you keep those boundaries in mind, the current implementation becomes much easier to navigate.
