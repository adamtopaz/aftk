# Future Tool Directions for Autoformalization

This roadmap extends the current AFTK design:

- **Informalize** organizes the blueprint layer,
- **AFTK hub** supports semantic query + transient proof exploration,
- **the shared custom toolset** (`createAFTKTools`) and **the pi extension wrapper** are the current tool surfaces for AFTK hub methods.

The goal is to improve agent reliability in the loop:

1. pick next target from blueprint state,
2. explore local proof options safely,
3. commit only validated formal proof text.

A core assumption is combined usage: Informalize manages blueprint ids/notes, while
AFTK hub queries Lean semantics and can retrieve those notes via hover at informal terms.

---

## Current baseline

Already available:

- Lifecycle: `open`, `close`, `shutdown`
- Infoview-like queries: `load_node`, `get_hover`, `get_plain_goal`, `get_plain_term_goal`, `get_infoview`
- Tactic exploration: `get_goals`, `run_tactic`, `run_tactic_steps`
- Blueprint queries (CLI): `status`, `deps`, `decls`, `decl`, `locations`, `location`

---

## Next framework layer above the current baseline

The next development target is the broader workflow defined in `docs/workflow.md`.
The main framework pieces still missing around the current Informalize+AFTK base are listed in `docs/components.md`.

In particular, the roadmap now includes:

- faithful source ingestion and source-packet storage,
- a knowledge store with query and writeback APIs,
- explicit scaffold-node management beyond current declaration tracking,
- frontier detection and readiness classification for leaf nodes,
- source-gap detection and source acquisition support,
- scaffold refinement and workflow orchestration.

These additions sit *above* the current AFTK hub and Informalize layers and are what turn the repository from a set of local tools into a full autoformalization framework.

## Highest-priority additions

### 1) Structured goals/context

`aftk_get_goal_structured { path, id }`

Return stable JSON for target + hypotheses (not only pretty text), enabling better ranking and replay.

### 2) Diagnostics API

`aftk_get_diagnostics { path, range?, severity? }`

Support repair loops after generated edits fail.

### 3) Candidate tactic branching in one call

`aftk_run_tactic_candidates { path, id, tactics: [...] }`

Try many one-step candidates from the same node and return per-candidate outcomes.

### 4) Premise retrieval

- `aftk_search_decls`
- `aftk_applicable_lemmas`

Reduce search entropy for `apply`, `rw`, `simp`, `exact`.

---

## Informalize-aware additions

Expose blueprint data through hub tools (in addition to CLI), e.g.:

- `aftk_informal_status`
- `aftk_informal_deps`
- `aftk_informal_decls`
- `aftk_informal_locations`
- `aftk_informal_location`
- `aftk_informal_frontier`

This would let one agent session plan and execute without switching channels.

---

## Design constraints for agent reliability

Prefer APIs with:

- explicit structured fields over plain text blobs,
- deterministic identifiers for branch bookkeeping,
- bounded outputs (`limit`, truncation metadata),
- explicit timeout controls,
- clear error categories (parse, unification, missing instance, unsolved goals).

These reduce ambiguity in autonomous proof/search loops.
