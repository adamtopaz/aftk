# AFTK: Agent-Oriented Autoformalization Toolkit for Lean

AFTK provides **two complementary layers** for autoformalization:

1. **Informalize**: build and track an *informal blueprint* of the formalization project.
2. **AFTK hub + pi extension**: query Lean semantic state and explore tactic strategies transiently.

The intended workflow is:

- start with high-level mathematical structure,
- encode that structure as blueprint placeholders,
- track dependencies and natural-language context,
- gradually refine toward direct Lean formalization.

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
- a CLI for querying blueprint status/dependencies/locations.

### Core syntax

```lean
informal[Foo.bar]
informal[Foo.bar] x y
informal[Foo.bar.baz] x y
informal x y
```

With a location id, Informalize resolves markdown paths under `informal/`:

- `Foo.bar` -> `informal/Foo/bar.md`
- `Foo.bar.baz` -> `informal/Foo/bar/baz.md`

The markdown file must exist when elaborating `informal[...]`.

### What gets tracked

For each declaration containing `informal`, Informalize records:

- declaration name,
- deduplicated set of referenced location ids (possibly empty for bare `informal`).

This gives a project-level map between:

- Lean declarations,
- natural-language blueprint fragments,
- declaration-level dependency structure (via CLI `deps`).

### Informal terms as placeholders (similar to `sorry`)

`informal` terms are regular Lean terms, so agents can use them as typed placeholders
inside declaration values and proofs while a target is still being refined.

This is intentionally similar in spirit to `sorry`-driven workflows, except that:

- placeholders can be linked to structured blueprint ids (`informal[...]`), and
- each id can carry markdown notes that are queryable later.

### CLI (for AI agent planning)

```bash
lake exe informalize status --module <Module.Name>
lake exe informalize deps --module <Module.Name>
lake exe informalize decls --module <Module.Name>
lake exe informalize decl --module <Module.Name> --decl <Decl.Name>
lake exe informalize locations --module <Module.Name>
lake exe informalize location --module <Module.Name> --location <Location.Name>
```

These commands are intended to support agent planning/triage over the blueprint.

---

## Part 2: AFTK hub + pi extension (semantic query + proof exploration)

AFTK ships two Lean JSON-RPC executables:

- `aftk_file_worker`: file-scoped analysis/tactic worker
- `aftk_server`: hub process managing multiple file workers

And a pi extension:

- `extensions/aftk-hub.ts`

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

Because Informalize attaches markdown content to informal terms and AFTK exposes hover,
this creates a direct bridge from natural-language planning notes to proof search.

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

```bash
lake build
```

Build specific executables:

```bash
lake build aftk_server aftk_file_worker informalize
```

---

## Install pi extension (from downstream project)

```bash
lake run setup_pi_extension
# or
lake run aftk/setup_pi_extension
```

This resolves the AFTK package path and runs `pi install -l <path-to-aftk-extension>`.

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

1. **Model high-level plan** with `informal[...]` placeholders and markdown blueprint notes.
2. **Query blueprint state** via `informalize` CLI (`status`, `deps`, `decls`, `locations`, ...).
3. **Select a local formalization target** based on dependency/frontier information.
4. **Query semantic + note context together** with AFTK (`get_hover`, goals, term-goals).
   - At informal terms, hover can include blueprint markdown content.
5. **Explore tactics transiently** with `run_tactic` / `run_tactic_steps`.
6. **Write/update natural-language strategy notes** in the linked markdown file as you explore.
7. **Commit only final proof text** to Lean source once a strategy is validated.
8. Repeat until blueprint placeholders are replaced by direct formalization.

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

- Informalize overview: `docs/informalize/README.md`
- Informal id rules: `docs/informalize/IdReference.md`
- AFTK hub + extension details: `docs/aftk/README.md`
- End-to-end agent workflow playbook: `docs/agent-playbook.md`
- Roadmap ideas: `docs/future/autoformalization-tools.md`
