# AFTK Hub Tools (shared custom toolset + pi extension wrapper)

This document describes the **agent-facing Lean interaction layer** of AFTK.

AFTK hub is designed to let AI agents:

- query semantic information from Lean files (infoview-like data),
- inspect goals at tactic points,
- explore tactic strategies transiently before writing final proofs.

Within the broader workflow in `docs/workflow.md`, AFTK is the Lean-facing execution layer used after a scaffold node has been selected for local formalization.

---

## Architecture

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

---

## Agent surfaces

### Shared custom toolset

AFTK's canonical TypeScript implementation lives at:

- `lambda/src/aftk-tools.ts`

It exports `createAFTKTools(...)`, which returns:

- `tools` — custom pi tool definitions exposing the AFTK hub methods,
- `shutdown(graceful?)` — cleanup for the managed `aftk_server` process.

Use this when embedding AFTK tools into your own `@mariozechner/pi-coding-agent` SDK session or other TypeScript integration.

### Upstream `pi` extension wrapper

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

The Lake script resolves the AFTK package path, ensures its TypeScript dependencies are installed, and runs:

```bash
pi install -l <path-to-aftk-package>
```

If you are developing inside this AFTK repository clone, also run:

```bash
./scripts/setup-git-hooks.sh
```

This enables repository hooks that block:

- commits containing staged sensitive files, and
- pushes whose outgoing commits contain sensitive files.

Example sensitive paths include `.envrc`.

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

---

## Semantic query methods

For source-position methods, `line` and `col` are **1-based**.

- `load_node { path, line, col }`
  - returns tactic node ids available at that location.
- `get_hover { path, line, col }`
  - returns plain hover text (if available).
- `get_plain_goal { path, line, col }`
  - returns pretty-printed goal-state content.
- `get_plain_term_goal { path, line, col }`
  - returns expected type information at term position.
- `get_infoview { path, line, col }`
  - bundles hover + goal + term-goal views.

These are intended as machine-queryable analogues of editor infoview inspection.

### Informalize synergy via hover

When a declaration uses `informal[Some.Id]`, the markdown content attached to that
Informalize id can be surfaced as hover information. Agents can query it with:

- `aftk_get_hover` (from the shared toolset or the pi extension wrapper), or
- `get_hover` (hub RPC).

This lets an agent recover natural-language blueprint context directly from code locations
while doing formal proof work.

---

## Tactic exploration methods

- `get_goals { path, id }`
  - returns current unsolved goals for a node id.
- `run_tactic { path, id, tactic }`
  - applies one tactic step and returns `{ goals, nextId }`.
- `run_tactic_steps { path, id, tactics }`
  - applies a sequence of tactic steps in order.

### How to use `run_tactic_steps` in search

`run_tactic_steps` runs one linear candidate sequence.

To do branch exploration, agents typically:

1. start from the same initial `id`,
2. try multiple candidate tactic sequences (multiple calls),
3. compare outputs/errors,
4. continue from the most promising returned `nextId`.

---

## Transient-state contract (important)

AFTK tactic exploration is intentionally **transient**.

Node ids represent in-memory exploratory states inside a worker session.
They are not final proof artifacts.

Agents should treat this as an exploration phase:

- probe candidate tactics,
- evaluate progress via resulting goals,
- capture strategy notes in markdown files linked by `informal[...]` ids,
- then write an explicit Lean proof script in the source file.

Do not rely on long-lived persistence of exploratory node ids.

### Example combined loop (Informalize + AFTK)

1. Add a placeholder in Lean: `informal[Domain.Topic.statement]`.
2. Add/update notes in `informal/Domain/Topic/statement.md`.
3. Use `aftk_get_hover` at that term to pull those notes into agent context.
4. Use `aftk_load_node` + `aftk_run_tactic`/`aftk_run_tactic_steps` to explore proof moves.
5. Keep refining markdown strategy notes as exploration proceeds.
6. Replace placeholder with finalized tactic proof text.

This pattern keeps planning notes and proof search tightly synchronized.

---

## Error model

Hub-level errors:

- `-32010`: file is not open
- `-32011`: file changed; reopen required
- `-32012`: worker unavailable

Worker-side tactic parse/elaboration failures are surfaced as JSON-RPC errors.

---

## Minimal JSON-RPC flow

```text
open(path)
load_node(path, line, col)
get_goals(path, id)
run_tactic / run_tactic_steps(path, id, ...)
close(path)            # optional
shutdown()             # when session ends
```

Use this together with Informalize CLI and `informal[...]` placeholders:

- Informalize helps agents plan *what* to formalize next.
- AFTK hub helps agents explore *how* to formalize it in Lean.
- Hover on informal terms can pull in natural-language markdown notes.
- Informal terms can serve as typed placeholders while proof search is ongoing.

This combined loop is the intended local formalization inner loop within the larger autoformalization workflow.
