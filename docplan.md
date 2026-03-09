# Documentation merge-to-main plan

## Scope reviewed

I reviewed the repository-authored tracked Markdown in:

- `README.md`
- `docs/**`
- `plan.md`
- `plans/**`
- `.pi/APPEND_SYSTEM.md`
- the fixture/data Markdown under `tests/**`

I did **not** include vendored Markdown under `node_modules/` or `.lake/` in the update scope.
The `tests/**.md` files are fixture data rather than prose docs, and `.pi/APPEND_SYSTEM.md` is a generated artifact.

## Main findings

1. **The active docs are mostly implementation-accurate, but the top-level framing is still rewrite-branch framing.**
   - `README.md`, `docs/README.md`, and `docs/architecture.md` still describe this repository as a “rewrite worktree”.
   - That wording becomes wrong as soon as this branch becomes `main`.

2. **`plan.md` is now stale enough to be misleading.**
   - It still talks about a separate rewrite worktree and a separate main-branch worktree.
   - It contains absolute local paths like `/home/dev/aftk` and `/home/dev/aftk_rewrite`.
   - It still mentions old planned interfaces such as `lake exe aftk kb ...`, which no longer match the implementation.
   - It describes server/toolkit intentions that the current implementation docs have deliberately narrowed or changed.

3. **The biggest documentation contradiction is in the toolkit/setup plan docs.**
   - `plans/toolkit.md`
   - `plans/toolkit/*.md`
   - `plans/setup.md`
   
   These still say the toolkit/setup work is “Not implemented”, talk about Bun-era placeholder scaffolding, and refer to `lakefile.toml` as current-repo reality, even though the toolkit and setup script are implemented and documented under `docs/toolkit/**` and `docs/aftk_setup.md`.

4. **The docs/plans taxonomy is not clear enough for a post-merge repository.**
   Right now a new reader can easily encounter:
   - `README.md`
   - `docs/architecture.md`
   - `plan.md`
   - `plans/**`
   
   and not know which files describe:
   - the current implementation,
   - the remaining roadmap,
   - or historical rewrite-era design reasoning.

5. **The knowledge-base, informal, and server plan docs are much closer to reality, but still carry rewrite-era framing.**
   Their status blocks are mostly honest, but many still contain:
   - “rewrite worktree” language,
   - “main-worktree” research references,
   - absolute local file paths,
   - and in a few places stale `lakefile.toml` references.
   
   Those are less urgent than the toolkit/setup contradictions, but they should be either cleaned up or explicitly marked as historical design notes.

6. **The layer docs under `docs/` are mostly in good shape.**
   - `docs/knowledgebase/**`, `docs/informal/**`, `docs/server/**`, and `docs/toolkit/**` are generally aligned with the code.
   - The main work there is mostly wording cleanup, consistency, and cross-link cleanup rather than substantive rewrites.

7. **Generated and fixture Markdown should be treated specially.**
   - `.pi/APPEND_SYSTEM.md` should only be changed by updating `lakefile.lean` and regenerating it.
   - `tests/**.md` fixture files should generally not be rewritten as part of doc cleanup.

## Recommended post-merge documentation model

We should make the repository’s documentation split explicit:

- **`README.md`** = front door / project overview
- **`docs/**`** = current implementation documentation
- **`plan.md`** = current roadmap and intentionally deferred work
- **`plans/**`** = detailed design notes, design rationale, and historical component plans
- **`.pi/APPEND_SYSTEM.md`** = generated prompt artifact, not source documentation
- **`tests/**.md`** = fixtures, not human-facing docs

That split is already close to what the repository wants, but it needs to be made explicit and consistent.

## Priority order

### Merge blockers

1. `README.md`
2. `docs/README.md`
3. `docs/architecture.md`
4. `plan.md`
5. `plans/toolkit.md`
6. `plans/toolkit/*.md`
7. `plans/setup.md`
8. a new `plans/README.md` or equivalent taxonomy note

### Important but not blocking if time is tight

1. `plans/knowledgebase.md`
2. `plans/informal.md`
3. `plans/server.md`
4. header/status cleanup across `plans/**`
5. wording cleanup across the layer docs in `docs/**`

### Low priority / likely no-op

1. `tests/**.md` fixture content
2. `.pi/APPEND_SYSTEM.md` content, unless we decide the generated prompt wording should change

## Work plan

### Phase 1 — Fix the repository entry points

**Files:**
- `README.md`
- `docs/README.md`
- `docs/architecture.md`

**Actions:**
- Remove “rewrite worktree” framing.
- Present the repository as the current `aftk` codebase, not a temporary branch.
- Keep the important implementation boundary explicit: the AI autoformalization layer is still not implemented.
- Make the remaining roadmap concise and point readers to `plan.md` for future work.
- Keep the four implemented layers prominent:
  - knowledge base
  - informal
  - server/file-worker
  - toolkit/pi integration

**Specific issues to fix:**
- `README.md` opening sentence.
- `README.md` summary language like “the current rewrite”.
- `docs/README.md` opening and closing paragraphs.
- `docs/architecture.md` opening paragraph and any “in this worktree today” wording.

**Desired outcome:**
A new reader landing on the repo should immediately get the correct post-merge picture.

---

### Phase 2 — Replace the stale high-level rewrite plan with a current roadmap

**File:**
- `plan.md`

**Actions:**
- Rewrite `plan.md` so it becomes a **current roadmap**, not a rewrite-process document.
- Remove:
  - separate-worktree instructions,
  - local absolute paths,
  - no-copy-from-old-worktree guidance,
  - stale command names such as `lake exe aftk kb ...`.
- Keep what is still valuable:
  - the layered architecture,
  - the fact that canonical prose lives in the knowledge base,
  - the major deferred areas.
- Reframe the remaining work around the actual current state:
  - AI autoformalization/orchestration layer
  - knowledge-base indexing
  - knowledge-base repair tooling
  - any deliberately deferred toolkit mutation/admin coverage
  - any deliberately deferred server evolution

**Recommendation:**
Keep the file path `plan.md`, but change its role to “roadmap from the current main branch state”. That minimizes link churn.

**Desired outcome:**
`plan.md` should complement `docs/architecture.md` instead of contradicting it.

---

### Phase 3 — Make the docs/plans split explicit

**Files:**
- new `plans/README.md` (recommended)
- possibly small edits in `README.md` and `docs/README.md`

**Actions:**
- Add a short index/explainer under `plans/` that says what `plans/**` is for.
- Explicitly distinguish:
  - current implementation docs (`docs/**`)
  - roadmap (`plan.md`)
  - detailed design/historical component plans (`plans/**`)
- Add a short status vocabulary for plan files, e.g.:
  - `Implemented`
  - `Implemented with deferred follow-ons`
  - `Deferred`
  - `Historical design note`

**Why this matters:**
This is the cheapest way to keep the large body of plan docs useful without needing a full prose rewrite of every historical research section before merge.

---

### Phase 4 — Fix the toolkit/setup plan files that are now plainly false

**Files:**
- `plans/toolkit.md`
- `plans/toolkit/layout.md`
- `plans/toolkit/runtime.md`
- `plans/toolkit/server-client.md`
- `plans/toolkit/lean-tools.md`
- `plans/toolkit/knowledgebase-tools.md`
- `plans/toolkit/informal-tools.md`
- `plans/toolkit/output.md`
- `plans/toolkit/pi-integration.md`
- `plans/toolkit/testing.md`
- `plans/setup.md`

**Actions:**
- Update the status blocks from “Not implemented” to the real current state.
- Remove or correct now-false statements about:
  - Bun placeholder scaffolding,
  - missing toolkit implementation,
  - `index.ts` as placeholder-only implementation,
  - `lakefile.toml` as the current config reality,
  - setup not existing yet.
- Add short notes pointing to the authoritative implementation docs:
  - `docs/toolkit/overview.md`
  - `docs/toolkit/library.md`
  - `docs/toolkit/testing.md`
  - `docs/aftk_setup.md`
- Where full line-by-line updates would be too large, do at least:
  - status block
  - opening summary paragraph
  - “last updated basis” line
  - concluding summary
  - any top-level claims that are now materially false

**Recommendation:**
Bring these files onto the same pattern already used successfully by many knowledge-base/informal/server component plans: “code has now been added; this remains a design/status document”.

**Desired outcome:**
No prominent toolkit/setup plan file should claim the toolkit or setup layer is missing.

---

### Phase 5 — Normalize the top-level layer plans

**Files:**
- `plans/knowledgebase.md`
- `plans/informal.md`
- `plans/server.md`

**Actions:**
- Reword top-level introductions so they do not depend on rewrite-branch framing.
- Remove or soften references to a separate main-branch worktree where those references are no longer needed.
- Decide whether `plans/knowledgebase.md` should keep “Partially implemented” or move to something like:
  - “Implemented as the current v1 foundation; indexing/repair remain deferred”.
- Check for stale repo-structure references such as `lakefile.toml` where they refer to the current repo rather than general project discovery behavior.

**Desired outcome:**
The three layer-plan overviews should read like current design/status docs rather than branch-local rewrite notes.

---

### Phase 6 — Do a lighter sweep over the remaining component plans

**Files:**
- the rest of `plans/knowledgebase/**`
- the rest of `plans/informal/**`
- the rest of `plans/server/**`

**Actions:**
- Standardize status headers where helpful.
- Remove obviously stale “rewrite worktree” wording from the openings and summaries.
- For deep historical research sections that cite local paths or compare against the old worktree, either:
  - trim them if they are no longer useful, or
  - leave them but make it obvious they are historical design notes.
- Replace current-repo `lakefile.toml` references with `lakefile.lean` where appropriate.

**Recommendation:**
This does **not** need to be a full prose rewrite of every line before merge. A good status/header pass plus a clear `plans/README.md` may be enough.

---

### Phase 7 — Small consistency sweep over `docs/**`

**Files:**
- `docs/knowledgebase/**`
- `docs/informal/**`
- `docs/server/**`
- `docs/toolkit/**`
- `docs/aftk_setup.md`

**Actions:**
- Remove any remaining “rewrite worktree” phrasing in active docs.
- Keep wording like “rewrite-specific” only where it is actually describing an AFTK-specific design choice, or rename it to “AFTK-specific”.
- Ensure the docs consistently describe the remaining deferred work in the same way as `README.md` and `plan.md`.
- Make sure cross-links point readers to the right canonical documents.

**Observed note:**
The layer docs are already much closer to merge-ready than the plan docs, so this should be a relatively light pass.

---

### Phase 8 — Handle generated and fixture Markdown correctly

**Files:**
- `.pi/APPEND_SYSTEM.md`
- `tests/informal/knowledgebase-fixtures/**/*.md`
- `tests/server/fixtures/knowledgebase/**/*.md`

**Actions:**
- Treat `.pi/APPEND_SYSTEM.md` as generated output.
  - If prompt wording needs adjustment, update `lakefile.lean` and regenerate via `lake run aftk_setup`.
  - Do not hand-edit the generated Markdown.
- Leave the fixture Markdown alone unless a documentation example explicitly depends on changing it.

**Desired outcome:**
We do not waste time “cleaning up” files that are not actually user-facing documentation sources.

## Suggested acceptance criteria before merge

### Active documentation should pass these checks

- `README.md` no longer describes the repo as a rewrite worktree.
- `docs/README.md` and `docs/architecture.md` no longer describe the repo as a rewrite worktree.
- `plan.md` is a current roadmap, not a rewrite-process memo.
- `plans/toolkit.md`, `plans/toolkit/*.md`, and `plans/setup.md` no longer say “Not implemented”.
- The docs/plans split is explicitly explained somewhere obvious.

### Search-based cleanup checks

These searches should return either nothing or only intentionally historical sections:

- `rewrite worktree`
- `main-branch worktree`
- `/home/dev/aftk`
- `/home/dev/aftk_rewrite`
- `Hello via Bun`
- `lake exe aftk kb`

And these should return no false negatives in current docs:

- `rg -n "Overall status: Not implemented" plans/toolkit plans/setup.md`
- `rg -n "lakefile.toml" plan.md plans docs README.md` (except where dual `lakefile.toml`/`lakefile.lean` discovery is intentionally being documented)

### Optional smoke checks after doc edits

These are not strictly “doc edits”, but they are good sanity checks for the commands the docs describe:

- `lake exe aftk --help`
- `lake exe aftk knowledgebase --help`
- `lake exe aftk informal --help`
- `lake run aftk_setup --help`
- `npm run check`
- `lake test`
- `npm run test:toolkit`

## Minimal merge-ready subset if we want the fastest path

If we want the smallest set of doc changes that still makes the branch reasonable to merge into `main`, I would do this first:

1. `README.md`
2. `docs/README.md`
3. `docs/architecture.md`
4. `plan.md`
5. `plans/toolkit.md`
6. `plans/toolkit/*.md`
7. `plans/setup.md`
8. add `plans/README.md`

That removes the most confusing contradictions immediately.

## Nice-to-have follow-up after the merge-ready pass

- broader wording cleanup across all component plans
- fuller historical cleanup of embedded local-path research references
- a more polished roadmap section for post-toolkit work
- any prompt wording refinement for the generated `.pi/APPEND_SYSTEM.md`

## Bottom line

The documentation is **close** to merge-ready in `README.md` and `docs/**`, but `plan.md` and especially the toolkit/setup plan files still describe a pre-implementation rewrite state. The key job is not rewriting every doc from scratch; it is:

1. changing the repo’s top-level framing from “rewrite branch” to “current main branch state”,
2. turning `plan.md` into a real roadmap,
3. removing the now-false toolkit/setup “Not implemented” claims,
4. and making the `docs/` vs `plan.md` vs `plans/` split explicit.
