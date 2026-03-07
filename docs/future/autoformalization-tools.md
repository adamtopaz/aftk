# Future Tool Directions for Autoformalization

This roadmap extends the current AFTK design:

- **Informalize** organizes the blueprint layer,
- **AFTK knowledge-base CLI** provides repository-local storage/query/writeback for sources, packets, knowledge entries, and provenance,
- **AFTK hub** supports semantic query + transient proof exploration,
- **the shared custom toolset** (`createAFTKTools`) and **the pi extension wrapper** are the current tool surfaces for AFTK hub methods.

The goal is to improve agent reliability in the loop:

1. register and retain useful project knowledge in-repo,
2. pick the next target from scaffold + knowledge state,
3. explore local proof options safely,
4. commit only validated formal proof text.

A core assumption remains combined usage: Informalize manages blueprint ids/notes,
AFTK knowledge CLI manages source/knowledge memory, and AFTK hub queries Lean semantics
while formalization is happening.

---

## Current baseline

Already available:

- Knowledge-base CLI:
  - `store init | validate | stats`
  - `source list | show | validate | register | update | remove`
  - `packet list | show | validate | ingest | update | remove`
  - `kb list | show | validate | query | create | update | remove`
  - `kb add/remove-tag`, `kb add/remove-link`, `kb add/remove-scaffold-ref`
- File-backed repository-local store under `aftk-data/`
- Explicit `src.*`, `pkt.*`, and `kb.*` ids
- Explicit provenance refs and `source_backed` vs `derived` knowledge basis
- Blueprint queries/management (CLI): `status`, `deps`, `deps --by location`, `decls`, `decl`, `locations`, `location`, `meta ...`
- Optional Informalize metadata sidecars with CLI-managed persistence and default fallback when no JSON file exists
- Lifecycle: `open`, `close`, `shutdown`
- Infoview-like queries: `load_node`, `get_hover`, `get_plain_goal`, `get_plain_term_goal`, `get_infoview`
- Tactic exploration: `get_goals`, `run_tactic`, `run_tactic_steps`

---

## What is still missing above the current baseline

The next development target is the broader workflow defined in `docs/workflow.md`.
The main framework pieces still missing around the current Informalize + knowledge-store + AFTK hub base are listed in `docs/components.md`.

In particular, the roadmap now centers on:

- richer faithful source ingestion and normalization,
- automatic knowledge extraction on top of stored packets,
- explicit scaffold-node management beyond current declaration tracking,
- frontier detection and readiness classification for leaf nodes,
- source-gap detection and source acquisition support,
- scaffold refinement and workflow orchestration,
- verification-aware formalization writeback/reporting.

These additions sit *above* the current storage/query and Lean-execution layers.

---

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

### 4) Knowledge-extraction helpers above `aftk-data/`

Potential directions:

- packet-to-knowledge extraction helpers,
- schema-aware batch import/export,
- derived indexes for faster retrieval,
- provenance-preserving extraction reports.

### 5) Scaffold/knowledge integration helpers

Potential directions:

- validate Informalize `knowledgeRefs` against `kb.*` ids,
- query scaffold-adjacent knowledge directly from Informalize ids,
- expose frontier/readiness information through one agent-facing surface.

---

## Informalize-aware additions

Expose blueprint data through hub tools (in addition to CLI), e.g.:

- `aftk_informal_status`
- `aftk_informal_deps`
- `aftk_informal_decls`
- `aftk_informal_locations`
- `aftk_informal_location`
- `aftk_informal_frontier`

This would let one agent session plan, retrieve knowledge, and execute without switching channels as often.

---

## Design constraints for agent reliability

Prefer APIs with:

- explicit structured fields over plain text blobs,
- deterministic identifiers for branch bookkeeping,
- bounded outputs (`limit`, truncation metadata),
- explicit timeout controls,
- clear error categories (parse, unification, missing instance, unsolved goals),
- explicit provenance rather than inferred provenance.

These reduce ambiguity in autonomous proof/search loops.
