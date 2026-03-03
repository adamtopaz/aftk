# Future Tool Ideas for Lean 4 Autoformalization

This document captures candidate AFTK/hub tools that could improve autoformalization quality and reliability beyond the current capabilities.

## Current baseline

Today, AFTK already supports:

- file/session lifecycle: `open`, `close`, `shutdown`
- source-position inspection: `load_node`, `get_hover`, `get_plain_goal`, `get_plain_term_goal`, `get_infoview`
- tactic execution: `get_goals`, `run_tactic`, `run_tactic_steps`

These are strong primitives. The next major gains likely come from:

1. **structured context extraction** (machine-friendly goal/hypothesis data)
2. **premise search/ranking** (finding relevant lemmas quickly)
3. **branching + recovery loops** (try many candidates, keep best)
4. **failure analysis** (targeted repair after generation errors)

---

## Proposed tools

## 1) `aftk_get_goal_structured`

Return goals and local context in structured JSON (instead of only pretty-printed strings).

**Why it helps**
- LLMs can reason over stable fields (`hypotheses`, `target`, binder names, dependencies).
- Easier downstream ranking and analytics.

**Sketch**
- Params: `{ path, id }`
- Result: `{ goals: [{ mvarId, target, hypotheses: [{ fvarId, name, type, value? }] }] }`

---

## 2) `aftk_get_diagnostics`

Return diagnostics (errors/warnings/info) for file/range, including ranges and severity.

**Why it helps**
- Enables robust repair loops after failed generated code.
- Allows selective retries on only broken declarations.

**Sketch**
- Params: `{ path, range?: {start, stop}, severities?: ["error"|"warning"|"info"] }`
- Result: `{ diagnostics: [{ severity, message, range, code? }] }`

---

## 3) `aftk_try_term`

Try elaborating a candidate term against the current expected type/context.

**Why it helps**
- Supports term-style generation loops (`exact ?`, lambda terms, rewriting candidates).
- Separates parse/elaboration validation from full tactic scripts.

**Sketch**
- Params: `{ path, id, term }`
- Result: `{ ok: Bool, goals?: [...], elaboratedTerm?: String, error?: {...} }`

---

## 4) `aftk_search_decls`

Search declarations by name/type pattern/namespace/module.

**Why it helps**
- Premise retrieval is often the bottleneck in autoformalization.
- Better lemma discovery means fewer random tactic attempts.

**Sketch**
- Params: `{ path, query?, typePattern?, namespace?, module?, limit? }`
- Result: `{ matches: [{ name, type, doc?, score }] }`

---

## 5) `aftk_applicable_lemmas`

Return a ranked shortlist of lemmas likely useful for the current goal.

**Why it helps**
- Gives focused candidates for `apply`, `exact`, `rw`, `simp`.
- Reduces search space and token usage.

**Sketch**
- Params: `{ path, id, limit?, modes?: ["apply","rw","simp"] }`
- Result: `{ lemmas: [{ name, type, modeHints, score, reason }] }`

---

## 6) `aftk_run_tactic_candidates`

Run multiple tactic candidates from one node and return all outcomes.

**Why it helps**
- Native branch-and-bound support for proof search.
- Lets clients keep successful branches and discard failures quickly.

**Sketch**
- Params: `{ path, id, tactics: [String], maxSuccesses?, timeoutMs? }`
- Result: `{ results: [{ tactic, ok, nextId?, goals?, error? }] }`

---

## 7) `aftk_checkpoint` / `aftk_restore`

Explicit snapshot/restore for tactic state nodes.

**Why it helps**
- Cheap backtracking without recomputing from source positions.
- Better for tree search and beam search agents.

**Sketch**
- `aftk_checkpoint` params: `{ path, id }` -> `{ checkpointId }`
- `aftk_restore` params: `{ path, checkpointId }` -> `{ id }`

---

## 8) `aftk_goal_diff`

Explain how goals/context changed after a tactic.

**Why it helps**
- Improves tactic ranking signals.
- Helps understand whether progress happened (goal count/shape/context changes).

**Sketch**
- Params: `{ path, beforeId, afterId }`
- Result: `{ addedGoals, removedGoals, changedGoals, addedHyps, removedHyps }`

---

## 9) `aftk_explain_failure`

Classify failures and suggest targeted next actions.

**Why it helps**
- Turns raw Lean error text into actionable categories.
- Better automated retry strategies.

**Sketch**
- Params: `{ path, error, context?: { id, tactic?, term? } }`
- Result: `{ category, confidence, suggestions: [String], relatedHints?: [...] }`

Example categories:
- parse error
- unification mismatch
- missing instance / typeclass synthesis
- unsolved goals
- rewrite mismatch

---

## 10) `aftk_minimize_proof`

Minimize/simplify successful tactic sequences.

**Why it helps**
- Produces cleaner final proofs after exploratory search.
- Useful post-processing for generated scripts.

**Sketch**
- Params: `{ path, id, tactics: [String], objective?: "length"|"readability" }`
- Result: `{ minimizedTactics, stats: { original, minimized } }`

---

## 11) `aftk_extract_holes`

Enumerate incomplete proof/program holes and their expected types.

**Why it helps**
- Enables batch autoformalization planning across files/modules.
- Provides queueing input for proof synthesis agents.

**Sketch**
- Params: `{ path, includeSorry?: Bool, includeSynthetic?: Bool }`
- Result: `{ holes: [{ declName, range, expectedType, localContextSummary }] }`

---

## 12) Informalize-aware tools

Given the existing `Informalize` extension and CLI, hub-level tools could expose this data directly.

Candidate tools:

- `aftk_informal_status`
- `aftk_informal_deps`
- `aftk_informal_decls`
- `aftk_informal_locations`
- `aftk_informal_location`
- `aftk_informal_unformalized_queue` (new: priority queue for declarations/locations to formalize)

**Why it helps**
- Connects markdown references directly to formalization workflows.
- Supports backlog triage and dependency-aware scheduling.

---

## Recommended implementation order (MVP first)

### Phase 1 (highest ROI)
1. `aftk_get_goal_structured`
2. `aftk_get_diagnostics`
3. `aftk_search_decls`
4. `aftk_run_tactic_candidates`

### Phase 2 (search quality + control)
5. `aftk_applicable_lemmas`
6. `aftk_checkpoint` / `aftk_restore`
7. `aftk_goal_diff`

### Phase 3 (polish + integration)
8. `aftk_try_term`
9. `aftk_explain_failure`
10. `aftk_minimize_proof`
11. `aftk_extract_holes`
12. Informalize-aware tools

---

## Notes on API shape

For tool robustness, prefer:

- stable, explicit JSON fields over plain text blobs
- optional text renderings *in addition to* structured fields
- deterministic IDs for branch bookkeeping
- bounded result sizes (`limit`, truncation metadata)
- explicit timeout controls for expensive operations

These choices make downstream agent behavior more reliable and easier to evaluate.