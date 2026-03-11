# Implemented architecture

This document describes the current implementation state of the `aftk` codebase.
It is intentionally implementation-facing: it focuses on what is in code now, which files own which responsibilities, and where the current boundaries are.

## Current status

The architecture is organized into four layers:

1. Knowledge base
2. Informal
3. Server / file worker
4. AI autoformalization agents

Today, the first three layers are implemented.
The fourth layer — AI-agent orchestration — is still future work.

For the project-level vision and roadmap, see `docs/roadmap.md`.

## Layer summary

| Layer | Current status | Main entrypoints | Main code roots |
| --- | --- | --- | --- |
| Knowledge base | Implemented | `lake exe aftk knowledgebase ...`, `import AFTK.KnowledgeBase` | `AFTK/KnowledgeBase*.lean`, `AFTK/KnowledgeBase/**` |
| Informal | Implemented | `lake exe aftk informal ...`, `import AFTK.Informal` | `AFTK/Informal*.lean`, `AFTK/Informal/**` |
| Server / file worker | Implemented | `lake exe aftk_server`, `lake exe aftk_file_worker <path>`, `import AFTK.Server`, `import AFTK.FileWorker` | `AFTK/Server*.lean`, `AFTK/Server/**`, `AFTK/FileWorker*.lean`, `AFTK/FileWorker/**` |
| AI agents | Not implemented | none yet | no agent-layer orchestration code yet |

## High-level dependency shape

The implemented stack is layered the way the broader project vision intends:

```text
AFTK.KnowledgeBase
        ↓
AFTK.Informal
        ↓
AFTK.Server / AFTK.FileWorker
```

More concretely:

- `AFTK.KnowledgeBase` owns canonical natural-language storage and filesystem semantics.
- `AFTK.Informal` resolves `informal[...]` references through the knowledge base and tracks which Lean declarations use them.
- `AFTK.Server` and `AFTK.FileWorker` expose a long-running JSON-RPC service for Lean queries and tactic exploration, and reuse the informal layer for richer hover at `informal[...]` sites.

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

### 4. AI-agent layer

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

### Derived or transient data

The current implementation has three important kinds of non-canonical state:

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

## Executables and user-facing commands

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
- `lakefile.lean` — Lake package config and executable definitions

## Testing structure

The repository currently has one test track.

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

## Important current limitations

These are deliberate or current implementation boundaries:

- Knowledge-base **repair** and **indexing** are still design-only.
- The informal layer is read/query oriented; it does not mutate knowledge-base content.
- `informal[...]` uses an explicit unsound placeholder axiom for gradual formalization.
- The server uses a **one-shot file snapshot** model.
  It does not support in-memory versioned edits.
- File changes invalidate workers by file stamp and require reopen.
- The AI autoformalization agent layer is not implemented yet.

## Practical mental model

A good short mental model of the current codebase is:

- the **knowledge base** is the source of truth for prose,
- the **informal layer** turns knowledge-base node ids into Lean placeholders plus trackable declaration metadata,
- the **server layer** exposes Lean/editor-style queries over real files while enriching `informal[...]` hovers through the lower layers,
- and higher-level automation remains future work rather than a currently implemented layer.

If you keep those boundaries in mind, the current implementation becomes much easier to navigate.
