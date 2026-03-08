# Implemented architecture

This document describes the current implementation state of the rewrite worktree.
It is intentionally implementation-facing: it focuses on what is in code now, not only on the broader architectural plan.

## Current status

The rewrite plan describes five layers:

1. Knowledge base
2. Informal
3. Server / file worker
4. Toolkit
5. AI autoformalization agents

Today, the first three layers are implemented in Lean.
The last two layers are still future work.

## Layer summary

| Layer | Current status | Main entrypoints |
| --- | --- | --- |
| Knowledge base | Implemented | `lake exe aftk knowledgebase ...` |
| Informal | Implemented | `lake exe aftk informal ...`, `import AFTK.Informal` |
| Server / file worker | Implemented | `lake exe aftk_server`, `lake exe aftk_file_worker <path>` |
| Toolkit | Not implemented | `index.ts` is only a placeholder |
| AI agents | Not implemented | no agent layer code yet |

## High-level dependency shape

The implemented Lean stack is layered exactly the way the top-level plan intends:

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

## What is canonical, and where

### Canonical natural-language data

Canonical prose lives only in the knowledge base:

- Markdown body: `knowledgebase/nodes/**/*.md`
- metadata JSON: `knowledgebase/nodes/**/*.json`
- storage manifest: `knowledgebase/manifest.json`

The informal layer does **not** introduce a second prose store.
It only stores bridge-specific declaration/reference tracking inside a Lean persistent environment extension.

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

## Executables and user-facing entrypoints

### Unified CLI

The top-level executable is:

```text
lake exe aftk <command> ...
```

It currently dispatches to:

- `knowledgebase`
- `informal`

### Standalone server executables

The server layer is exposed separately:

```text
lake exe aftk_server
lake exe aftk_file_worker <path>
```

`aftk_server` is the public JSON-RPC hub.
`aftk_file_worker` is the internal per-file worker executable spawned by the hub.

## Module layout

### Public library roots

- `AFTK.lean`
- `AFTK/KnowledgeBase.lean`
- `AFTK/Informal.lean`
- `AFTK/Server.lean`
- `AFTK/FileWorker.lean`

### Knowledge-base modules

- `AFTK/KnowledgeBase/Types.lean`
- `AFTK/KnowledgeBase/PathLayout.lean`
- `AFTK/KnowledgeBase/Serialization.lean`
- `AFTK/KnowledgeBase/Storage.lean`
- `AFTK/KnowledgeBase/Validation.lean`
- `AFTK/KnowledgeBase/Search.lean`
- `AFTK/KnowledgeBase/Cli/*`

### Informal modules

- `AFTK/Informal/Syntax.lean`
- `AFTK/Informal/Placeholder.lean`
- `AFTK/Informal/References.lean`
- `AFTK/Informal/Tracking.lean`
- `AFTK/Informal/Dependencies.lean`
- `AFTK/Informal/Presentation.lean`
- `AFTK/Informal/Options.lean`
- `AFTK/Informal/Elaborator.lean`
- `AFTK/Informal/Cli/*`

### Server / file-worker modules

- `AFTK/Server/Protocol.lean`
- `AFTK/Server/Transport.lean`
- `AFTK/Server/Hub.lean`
- `AFTK/Server/Main.lean`
- `AFTK/FileWorker/Context.lean`
- `AFTK/FileWorker/Queries.lean`
- `AFTK/FileWorker/TacticState.lean`
- `AFTK/FileWorker/Informal.lean`
- `AFTK/FileWorker/Handlers.lean`
- `AFTK/FileWorker/Main.lean`

## Testing structure

The repository uses a single Lake test driver:

```text
lake test
```

That driver runs three suite executables:

- `aftk_knowledgebase_test`
- `aftk_informal_test`
- `aftk_server_test`

The tests live under `AFTKTest/` and use checked-in fixtures under `tests/`.

## Important current limitations

These are deliberate or at least current implementation boundaries:

- Knowledge-base **repair** and **indexing** are still design-only.
- The informal layer is read/query oriented; it does not mutate knowledge-base content.
- `informal[...]` uses an explicit unsound placeholder axiom for gradual formalization.
- The server uses a **one-shot file snapshot** model.
  It does not support in-memory versioned edits.
- File changes invalidate workers by file stamp and require reopen.
- The TypeScript toolkit and AI-agent layers are not yet implemented.

## Practical mental model

A good short mental model of the current codebase is:

- the **knowledge base** is the source of truth for prose,
- the **informal layer** turns knowledge-base node ids into Lean placeholders plus trackable declaration metadata,
- and the **server layer** exposes Lean/editor-style queries over real files while enriching `informal[...]` hovers through the lower layers.

If you keep those three boundaries in mind, the current implementation becomes much easier to navigate.
