# AFTK: Knowledge-Base CLI + Hub Tools

This document describes the two AFTK surfaces that now exist in the repository:

1. **`lake exe aftk ...`** — a repository-local knowledge-base CLI.
2. **AFTK hub tools** — Lean semantic query + transient tactic exploration via
   `aftk_server`, `aftk_file_worker`, the shared custom toolset, and the pi extension wrapper.

Within the broader workflow in `docs/workflow.md`:

- the **knowledge-base CLI** is the repository memory layer for sources, packets, knowledge entries, and provenance,
- the **hub tools** are the Lean-facing execution layer used during direct formalization.

---

## Part 1: Knowledge-base CLI (`lake exe aftk ...`)

### Store model

AFTK stores knowledge-base data under a repository-local root:

- `aftk-data/store.json`

The CLI discovers the nearest ancestor containing that manifest, or you can override it with:

- `--store <Path>`

Current on-disk layout:

```text
aftk-data/
  store.json
  sources/
    ... source JSON records ...
  packets/
    ... packet JSON records ...
    ... packet markdown bodies ...
  knowledge/
    ... knowledge JSON records ...
    ... knowledge markdown bodies ...
```

Id families:

- `src.*` — source ids
- `pkt.*` — packet ids
- `kb.*` — knowledge ids

Example mapping:

- `src.paper.smith2024` -> `aftk-data/sources/paper/smith2024.json`
- `pkt.paper.smith2024.thm_2_3` ->
  - `aftk-data/packets/paper/smith2024/thm_2_3.json`
  - `aftk-data/packets/paper/smith2024/thm_2_3.md`
- `kb.group.definition` ->
  - `aftk-data/knowledge/group/definition.json`
  - `aftk-data/knowledge/group/definition.md`

### What is stored

#### Sources

Source records capture stable ids plus metadata such as:

- kind,
- title,
- authors,
- locator (`path`, `uri`, or freeform `note`),
- version/hash/license,
- tags,
- note.

#### Packets

Source packets capture:

- owning source id,
- title and optional summary,
- anchor ids,
- explicit provenance back to sources,
- tags,
- a markdown body sidecar.

#### Knowledge entries

Knowledge entries capture:

- stable `kb.*` id,
- kind,
- basis (`source_backed` or `derived`),
- title and optional summary,
- source refs,
- packet refs,
- scaffold refs (`Informalize` location ids),
- provenance refs,
- links to other knowledge entries,
- tags,
- a markdown body sidecar.

### Core commands

Initialize and inspect a store:

```bash
lake exe aftk store init
lake exe aftk store validate
lake exe aftk store stats --json
```

Register sources:

```bash
lake exe aftk source register \
  --id src.paper.smith2024 \
  --kind paper \
  --title "Smith 2024" \
  --path sources/smith2024.txt

lake exe aftk source list
lake exe aftk source show --id src.paper.smith2024 --json
lake exe aftk source validate --id src.paper.smith2024
```

Persist source packets:

```bash
lake exe aftk packet ingest \
  --id pkt.paper.smith2024.thm_2_3 \
  --source src.paper.smith2024 \
  --title "Theorem 2.3 excerpt" \
  --body-file tmp/thm_2_3.md \
  --anchor thm-2-3 \
  --prov-locator "Theorem 2.3"

lake exe aftk packet list --source src.paper.smith2024
lake exe aftk packet show --id pkt.paper.smith2024.thm_2_3
lake exe aftk packet validate --id pkt.paper.smith2024.thm_2_3
```

Create/query knowledge entries:

```bash
lake exe aftk kb create \
  --id kb.group.definition \
  --kind definition \
  --basis source_backed \
  --title "Definition of group" \
  --body-file tmp/group-definition.md \
  --source src.paper.smith2024 \
  --packet pkt.paper.smith2024.thm_2_3 \
  --location Algebra.Group.definition \
  --tag algebra

lake exe aftk kb show --id kb.group.definition
lake exe aftk kb query --source src.paper.smith2024 --json
lake exe aftk kb query --location Algebra.Group.definition
```

Mutate knowledge entries:

```bash
lake exe aftk kb add-tag --id kb.group.definition --tag reviewed
lake exe aftk kb add-link --id kb.group.definition --relation related --target kb.group.definition
lake exe aftk kb add-scaffold-ref --id kb.group.definition --location Algebra.Group.definition
```

Whole-record replacement updates are currently supported through `--from-json`:

```bash
lake exe aftk source update --id src.paper.smith2024 --from-json tmp/source.json
lake exe aftk packet update --id pkt.paper.smith2024.thm_2_3 --from-json tmp/packet.json --body-file tmp/thm_2_3.md
lake exe aftk kb update --id kb.group.definition --from-json tmp/kb.json --body-file tmp/group-definition.md
```

### Output modes

Main read/query commands support:

- plain text by default,
- `--json` for machine-readable output.

This includes:

- `store stats`
- `source list` / `source show`
- `packet list` / `packet show`
- `kb list` / `kb show` / `kb query`

### Current validation model

`store validate` checks at least:

- store manifest schema,
- record-local schema validity,
- unique ids within each family,
- packet -> source references,
- knowledge -> source/packet/knowledge references,
- provenance target validity,
- packet/knowledge markdown sidecar existence,
- source-backed knowledge entries carrying source/packet support,
- removal safety for referenced records.

### Current scope and limits

This first implementation is intentionally repository-local and file-backed.
It does **not** yet provide:

- PDF/OCR/document parsing,
- automatic extraction from raw sources,
- embeddings/vector retrieval,
- a remote store service,
- scaffold generation or orchestration.

So today the CLI is the stable persistence/query/writeback layer, not the entire workflow engine.

---

## Part 2: Hub tools (`aftk_server`, `aftk_file_worker`, pi surfaces)

### Architecture

AFTK provides two JSON-RPC executables:

- `aftk_server` (hub)
- `aftk_file_worker` (per-file worker)

The hub manages file workers and routes file-scoped requests.

Typical lifecycle:

1. `open` a Lean file in the hub,
2. query source-position and tactic-state information,
3. optionally `close` file,
4. `shutdown` hub when done.

If a file changes on disk, hub methods return `-32011` and the file must be reopened.

### Agent surfaces

#### Shared custom toolset

AFTK's canonical TypeScript implementation lives at:

- `lambda/src/aftk-tools.ts`

It exports `createAFTKTools(...)`, which returns:

- `tools` — custom pi tool definitions exposing the AFTK hub methods,
- `shutdown(graceful?)` — cleanup for the managed `aftk_server` process.

Use this when embedding AFTK tools into your own `@mariozechner/pi-coding-agent` SDK session or other TypeScript integration.

#### Upstream `pi` extension wrapper

AFTK also ships a thin pi extension wrapper at:

- `lambda/src/aftk-extension.ts`

This wrapper reuses the same tool implementation from `createAFTKTools(...)` and additionally registers:

- session shutdown cleanup, and
- the `aftk-extension-stop` command.

Install it into a downstream project with:

```bash
lake run setup_pi_extension
# or
lake run aftk/setup_pi_extension
```

### Exposed tool names

Both the shared toolset and the pi extension wrapper expose the same hub tool names:

- `aftk_open`
- `aftk_close`
- `aftk_load_node`
- `aftk_get_hover`
- `aftk_get_plain_goal`
- `aftk_get_plain_term_goal`
- `aftk_get_infoview`
- `aftk_get_goals`
- `aftk_run_tactic`
- `aftk_run_tactic_steps`
- `aftk_shutdown`

### Semantic query methods

For source-position methods, `line` and `col` are **1-based**.

- `load_node { path, line, col }`
- `get_hover { path, line, col }`
- `get_plain_goal { path, line, col }`
- `get_plain_term_goal { path, line, col }`
- `get_infoview { path, line, col }`

### Informalize synergy via hover

When a declaration uses `informal[Some.Id]`, AFTK hover can surface:

- the linked markdown content,
- effective Informalize metadata,
- scaffold context directly at the term location.

That makes the hub a useful bridge between blueprint planning and Lean proof search.

### Tactic exploration methods

- `get_goals { path, id }`
- `run_tactic { path, id, tactic }`
- `run_tactic_steps { path, id, tactics }`

These tactic states are intentionally transient. Agents should use them for exploration,
then write real Lean proof text afterward.

### Error model

Hub-level errors:

- `-32010`: file is not open
- `-32011`: file changed; reopen required
- `-32012`: worker unavailable

---

## Combined usage pattern

A typical project loop now looks like:

1. use `lake exe aftk source ...`, `packet ...`, and `kb ...` to build repository-local memory,
2. use `lake exe informalize ...` to manage scaffold ids/metadata,
3. use AFTK hover/goals/tactic exploration while formalizing selected scaffold nodes,
4. write useful outcomes back into `aftk-data/` and scaffold metadata.

That is the current practical AFTK workflow available in this repository.
