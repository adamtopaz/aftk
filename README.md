# AFTK: Agent-Oriented Autoformalization Toolkit for Lean

> [!WARNING]
> This repository is currently a place for experimentation with ideas about autoformalization.
> It is **not** production-ready and should not be relied on as a production system.

AFTK now provides **three complementary layers** for autoformalization:

1. **Informalize**: build and track an *informal blueprint* of the formalization project.
2. **AFTK knowledge-base CLI**: persist and query a repository-local source/packet/knowledge store.
3. **AFTK hub tools** (via the shared custom toolset or the pi extension wrapper): query Lean semantic state and explore tactic strategies transiently.

The intended workflow is:

- register sources and persist faithful source packets,
- build and update a source-backed knowledge store in-repo,
- generate an initial scaffold with blueprint placeholders,
- iterate over leaf scaffold nodes by gathering more sources, refining the scaffold, or formalizing ready leaves,
- use AFTK hub tools for local semantic queries and tactic exploration while formalizing.

See `docs/workflow.md` for the precise end-to-end loop and `docs/components.md` for the remaining framework pieces still to implement.

---

## Why this package exists

Direct one-shot formalization is often brittle. AFTK is designed for a **gradual refinement loop**:

- organize target theorems and definitions early,
- connect Lean declarations to human-readable math notes,
- expose machine-queryable project state to AI agents,
- let agents explore proof strategies before committing final proof scripts.

The blueprint is an **intermediate planning layer**, not the final endpoint.

---

## Part 1: Informalize (blueprint layer)

Informalize introduces:

- a term elaborator `informal[...]` / `informal ...`,
- an environment extension that tracks which declarations use `informal`,
- optional JSON metadata sidecars for blueprint nodes,
- a CLI for querying blueprint state and managing metadata.

### Core syntax

```lean
informal[Foo.bar]
informal[Foo.bar] x y
informal[Foo.bar.baz] x y
informal x y
```

With a location id, Informalize resolves sidecar paths under `informal/`:

- `Foo.bar` -> `informal/Foo/bar.md` and optional `informal/Foo/bar.json`
- `Foo.bar.baz` -> `informal/Foo/bar/baz.md` and optional `informal/Foo/bar/baz.json`

The markdown file must exist when elaborating `informal[...]`.
If the JSON metadata sidecar is missing, Informalize uses default metadata.
If the JSON sidecar exists but is invalid, elaboration fails.

### What gets tracked

For each declaration containing `informal`, Informalize records:

- declaration name,
- deduplicated set of referenced location ids (possibly empty for bare `informal`).

This gives a project-level map between:

- Lean declarations,
- natural-language blueprint fragments,
- optional machine-readable node metadata,
- declaration-level and location-level dependency structure (via CLI `deps`).

### Informal terms as placeholders (similar to `sorry`)

`informal` terms are regular Lean terms, so agents can use them as typed placeholders
inside declaration values and proofs while a target is still being refined.

This is intentionally similar in spirit to `sorry`-driven workflows, except that:

- placeholders can be linked to structured blueprint ids (`informal[...]`),
- each id can carry markdown notes plus optional structured metadata, and
- metadata is intended to be managed through the CLI rather than by editing JSON manually.

### CLI (for AI agent planning)

```bash
lake exe informalize status --module <Module.Name>
lake exe informalize deps --module <Module.Name>
lake exe informalize deps --module <Module.Name> --by location
lake exe informalize decls --module <Module.Name>
lake exe informalize decl --module <Module.Name> --decl <Decl.Name>
lake exe informalize locations --module <Module.Name>
lake exe informalize location --module <Module.Name> --location <Location.Name>
lake exe informalize meta show --location <Location.Name>
lake exe informalize meta set-status --location <Location.Name> --status ready
```

Use the `meta ...` commands to create/update JSON sidecars. If no sidecar exists yet,
Informalize uses default metadata and the first metadata mutation command materializes the file.
`--json` output is available for agent-facing machine consumption.

---

## Part 2: AFTK knowledge-base CLI

AFTK now ships a repository-local, file-backed knowledge-base CLI:

- executable: `lake exe aftk ...`
- store root: `aftk-data/`
- record families:
  - `src.*` — registered sources
  - `pkt.*` — persisted source packets
  - `kb.*` — knowledge entries

The store is designed to be:

- repository-local,
- git-inspectable,
- incrementally updateable,
- explicit about provenance,
- explicit about source-backed vs derived knowledge.

### What the CLI supports today

Store operations:

```bash
lake exe aftk store init
lake exe aftk store validate
lake exe aftk store stats --json
```

Source operations:

```bash
lake exe aftk source register --id src.paper.demo --kind paper --title "Demo" --path sources/demo.txt
lake exe aftk source list
lake exe aftk source show --id src.paper.demo --json
```

Source-packet operations:

```bash
lake exe aftk packet ingest \
  --id pkt.paper.demo.thm_1 \
  --source src.paper.demo \
  --title "Theorem 1 excerpt" \
  --body-file tmp/thm_1.md

lake exe aftk packet show --id pkt.paper.demo.thm_1
lake exe aftk packet list --source src.paper.demo
```

Knowledge-entry operations:

```bash
lake exe aftk kb create \
  --id kb.demo.statement \
  --kind theorem_statement \
  --basis source_backed \
  --title "Demo statement" \
  --body-file tmp/statement.md \
  --source src.paper.demo \
  --packet pkt.paper.demo.thm_1 \
  --location Demo.statement

lake exe aftk kb query --source src.paper.demo --json
lake exe aftk kb add-tag --id kb.demo.statement --tag demo
```

### Current storage model

AFTK stores structured metadata in JSON and long-form packet/knowledge bodies in markdown sidecars.

Example layout:

```text
aftk-data/
  store.json
  sources/
    paper/
      demo.json
  packets/
    paper/
      demo/
        thm_1.json
        thm_1.md
  knowledge/
    demo/
      statement.json
      statement.md
```

### Current scope

This implementation gives the workflow a practical, machine-facing in-repo memory layer.
It does **not** yet solve:

- document/PDF ingestion,
- automatic knowledge extraction,
- scaffold generation/orchestration,
- readiness/frontier automation,
- remote or service-backed storage.

Those follow-on pieces are tracked in `docs/components.md` and `docs/future/autoformalization-tools.md`.

---

## Part 3: AFTK hub tools (semantic query + proof exploration)

AFTK ships two Lean JSON-RPC executables:

- `aftk_file_worker`: file-scoped analysis/tactic worker
- `aftk_server`: hub process managing multiple file workers

Agent interaction surfaces:

- **shared custom toolset** via `lambda/src/aftk-tools.ts`, which exports `createAFTKTools(...)` for custom `@mariozechner/pi-coding-agent` SDK sessions.
- **pi extension wrapper** via `lambda/src/aftk-extension.ts`, which registers the same AFTK tools inside upstream `pi`.

### What agents use this for

- infoview-like semantic queries at source locations (`hover`, goals, expected term goal),
- loading tactic nodes from source positions,
- running one or many tactic steps from a given node id.

### Crucial synergy: use AFTK and Informalize together

AI agents are expected to use both layers in one loop.

A key pattern:

1. Put `informal[Blueprint.Id]` placeholders in Lean code.
2. Store strategy/context notes in `informal/.../*.md` for that id.
3. Query `aftk_get_hover` at the informal term location.
4. Recover natural-language notes directly in-agent while exploring tactics.
5. Convert successful exploration into final tactic proof text.

Because Informalize attaches markdown content and effective metadata to informal terms and AFTK exposes hover,
this creates a direct bridge from natural-language planning notes and scaffold status to proof search.

### Transient proof exploration model

`run_tactic` / `run_tactic_steps` produce new node ids in worker memory.

These exploratory states are **transient**:

- they are for search/experimentation,
- they are not persisted as final proof text,
- they disappear when workers are closed/restarted (e.g. file changes).

Expected agent behavior:

1. explore candidate tactic paths,
2. inspect resulting goals/output,
3. keep only promising branches,
4. write a real Lean proof script afterward.

---

## Build

Build everything in the workspace:

```bash
lake build
```

Build only core targets (this is what CI uses before tests):

```bash
lake build AFTK Informalize aftk aftk_file_worker aftk_server informalize
```

## Test

Run the full test suite:

```bash
lake exe tests
```

Informalize CLI and AFTK knowledge-base CLI integration checks are executed at test-runtime via
`lake exe tests` (instead of compile-time `run_cmd`) to keep CI build memory usage stable.

---

## Install repository git hooks (recommended)

AFTK ships repo-managed hooks that:

- block local commits if sensitive files are staged (including `git add -f`), and
- block `git push` if outgoing commits contain sensitive files.

Examples: `.envrc`, `.env`, `.env.local`.

Install once per clone:

```bash
./scripts/setup-git-hooks.sh
```

Customize blocked globs in `.githooks/sensitive-paths.txt`.

---

## Use the shared custom toolset

`lambda/src/aftk-tools.ts` is the canonical TypeScript implementation of the AFTK hub tools.
It exports `createAFTKTools(...)`, which returns:

- `tools` — the custom tool definitions to mount into a pi SDK session,
- `shutdown(graceful?)` — cleanup for the managed `aftk_server` process.

This is the intended integration point for custom TypeScript/SDK-based agent sessions.
The repository no longer ships a separate AFTK-specific CLI runner.

## pi extension wrapper

If you are using upstream `pi` directly, AFTK ships a thin extension wrapper at `lambda/src/aftk-extension.ts`.
It registers the same tool definitions exposed by `createAFTKTools(...)`.

Install it into the current project with:

```bash
lake run setup_pi_extension
# or
lake run aftk/setup_pi_extension
```

This resolves the AFTK package path, ensures its TypeScript dependencies are installed, and runs `pi install -l <path-to-aftk-package>`.

---

## Hub methods (quick reference)

Lifecycle:

- `open`
- `close`
- `shutdown`

Source-position inspection (`line`/`col` are 1-based):

- `load_node`
- `get_hover`
- `get_plain_goal`
- `get_plain_term_goal`
- `get_infoview`

Tactic-state operations:

- `get_goals`
- `run_tactic`
- `run_tactic_steps`

Common hub errors:

- `-32010`: file not open
- `-32011`: file changed; reopen required
- `-32012`: worker unavailable

---

## Recommended agent workflow

1. **Initialize a repository-local store** with `lake exe aftk store init`.
2. **Register sources and persist packets** with `lake exe aftk source ...` and `lake exe aftk packet ...`.
3. **Build/update the knowledge store** with `lake exe aftk kb ...`, preserving provenance and scaffold links.
4. **Create or refine scaffold nodes** with `informal[...]` placeholders and markdown notes.
5. **Query scaffold state** via `informalize` CLI (`status`, `deps`, `decls`, `locations`, `meta show`, ...).
6. **Select a leaf node** and classify it as ready, needing sources, or needing refinement.
7. **Gather more sources or refine the scaffold** until the selected node is small, precise, and supported.
8. **Use AFTK hub tools for the local Lean-facing formalization step** (`get_hover`, goals, tactic exploration).
   - At informal terms, hover can include blueprint markdown content plus effective metadata.
9. **Commit only final proof text** to Lean source once a strategy is validated, then update the scaffold/knowledge state and repeat.

For the detailed workflow, see `docs/workflow.md`. For the remaining implementation pieces around Informalize and AFTK, see `docs/components.md`.

---

## Important soundness note

`informal` elaborates through the unsound axiom:

```lean
axiom Informalize.Informal.{u} (tag : Lean.Name) (alpha : Sort u) : alpha
```

So Informalize is a planning/organization mechanism for gradual formalization,
not a substitute for completed formal proofs.

---

## Documentation map

- End-to-end workflow definition: `docs/workflow.md`
- Framework components to build next: `docs/components.md`
- Informalize overview: `docs/informalize/README.md`
- Informal id rules: `docs/informalize/IdReference.md`
- AFTK hub tool surfaces (shared custom toolset + pi extension wrapper): `docs/aftk/README.md`
- Lean-facing agent workflow playbook: `docs/agent-playbook.md`
- Roadmap ideas: `docs/future/autoformalization-tools.md`
