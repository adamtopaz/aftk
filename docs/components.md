# Components Needed for the Autoformalization Framework

This document identifies the components required to implement the end-to-end workflow in `docs/workflow.md`.

The goal is to build the larger framework around the pieces that already exist in this repository.

This document uses **knowledge store** and **knowledge base** interchangeably.

Status labels used below:

- **Existing** — already present in the repository.
- **Partial** — useful groundwork exists, but it does not yet provide the full framework role.
- **New** — needs to be implemented.

---

## Existing foundation in this repository

### 1. Informalize placeholder layer
**Status:** Existing

What it already provides:

- `informal[...]` placeholders in Lean,
- markdown-backed notes under `informal/`,
- optional JSON metadata sidecars for scaffold nodes,
- declaration-level tracking of which locations are referenced.

Why it matters:

- this is the natural anchor for scaffold nodes,
- it already gives us a way to represent unfinished formalization work inside Lean.

What it does **not** yet provide:

- a full scaffold graph service,
- automated frontier/readiness orchestration,
- source/knowledge integration.

### 2. Informalize CLI
**Status:** Existing

What it already provides:

- `status`, `deps`, `decls`, `decl`, `locations`, `location`,
- derived location-dependency queries via `deps --by location`,
- CLI-managed metadata inspection and mutation via `meta ...`.

Why it matters:

- useful for declaration-level frontier inspection,
- useful for connecting Lean declarations to informal ids.

What it does **not** yet provide:

- node-level frontier computation for refined sub-scaffolds,
- readiness classification beyond authored metadata,
- source-gap detection.

### 3. AFTK hub + tool surfaces
**Status:** Existing

What it already provides:

- hover and goal queries,
- tactic-node loading,
- transient tactic exploration,
- both shared TypeScript and pi-extension surfaces.

Why it matters:

- this is the local Lean-facing execution layer for ready nodes.

What it does **not** yet provide:

- source ingestion,
- knowledge-store retrieval,
- orchestration over the full scaffold loop.

### 4. Lean build/test workflow
**Status:** Partial

What it already provides:

- `lake build`,
- `lake exe tests`,
- a normal Lean project environment.

Why it matters:

- verified formalization must pass project validation.

What it does **not** yet provide:

- an explicit acceptance-gate component for workflow orchestration,
- structured reporting back into scaffold or knowledge state.

---

## Framework components to implement

### A. Source and corpus layer

#### 5. Source registry
**Status:** New

Responsibility:

- register every raw source intended for autoformalization.

Inputs:

- files, URLs, local notes, textbooks, papers, prior formal developments, etc.

Outputs:

- stable source ids,
- source metadata,
- version/hash information when available.

Why it is needed:

- the workflow is source-first,
- we need stable provenance from the beginning.

Minimal first version:

- a file-backed manifest is enough.

#### 6. Faithful source ingester / normalizer
**Status:** New

Responsibility:

- turn raw sources into faithful, agent-readable source packets.

Inputs:

- source records from the source registry.

Outputs:

- normalized text,
- structural anchors,
- chunked packets,
- provenance links to the original source.

Why it is needed:

- the agent needs a usable representation of the source material before any scaffold or formalization work can be trusted.

Important requirement:

- normalization must preserve structure and provenance rather than silently paraphrasing the source.

#### 7. Source-packet storage layer
**Status:** New

Responsibility:

- persist the ingested source packets in a form that can be queried later.

Outputs should support:

- lookup by source id,
- lookup by theorem/section anchors,
- chunk retrieval with provenance.

Why it is needed:

- knowledge extraction and later retrieval both depend on stable stored source packets.

---

### B. Knowledge-store layer

#### 8. Knowledge extraction pipeline
**Status:** New

Responsibility:

- derive reusable knowledge items from source packets.

Typical outputs:

- definition entries,
- theorem entries,
- notation mappings,
- examples,
- proof sketches,
- dependency hints.

Why it is needed:

- the agent should not repeatedly re-read raw sources for every local task.

#### 9. Knowledge store
**Status:** New

Responsibility:

- store retrievable mathematical knowledge derived from sources and later workflow steps.

The store must support at least:

- source-backed entries,
- agent-derived entries,
- links among entries,
- provenance,
- updates over time.

Why it is needed:

- it is the central memory of the workflow.

Important requirement:

- source-backed and agent-derived content must be clearly distinguished.

#### 10. Knowledge retrieval/query API
**Status:** New

Responsibility:

- let the agent query the knowledge store at any point in the workflow.

Typical queries:

- “what source-backed statements mention this concept?”,
- “what definitions or notation are relevant to this scaffold node?”,
- “what prior formalization attempts or examples exist for this topic?”.

Why it is needed:

- the user’s intended loop allows querying the knowledge base at any time.

#### 11. Knowledge writeback/update API
**Status:** New

Responsibility:

- let the agent add new material to the knowledge store at any point.

Examples:

- newly ingested sources,
- refined scaffold notes,
- successful formalization outcomes,
- failed-attempt diagnostics,
- derived strategy notes.

Why it is needed:

- the knowledge store must evolve as the project evolves.

#### 12. Provenance and citation layer
**Status:** New

Responsibility:

- track where each knowledge item, scaffold node, and formalization decision came from.

Why it is needed:

- source traceability is one of the main workflow invariants,
- without it, the knowledge store becomes unreliable.

---

### C. Scaffold-management layer

#### 13. Scaffold node schema and registry
**Status:** New

Responsibility:

- define the explicit data model for scaffold nodes and track all nodes in the project.

Each node should include at least:

- id,
- description,
- status,
- dependencies/children,
- links to Lean locations,
- links to knowledge entries and sources.

Why it is needed:

- current Informalize tracking is declaration-oriented,
- the framework needs explicit node-oriented control.

Relationship to existing code:

- `informal[...]` ids and markdown files are the obvious first anchor for this registry.

#### 14. Initial scaffold generator
**Status:** New

Responsibility:

- generate the first scaffold from the current target and knowledge store.

Typical work:

- decide which top-level declarations or subgoals should be represented as informal nodes,
- create initial notes and citations,
- populate Lean placeholders where appropriate.

Why it is needed:

- the workflow assumes the scaffold exists before leaf-wise iteration begins.

#### 15. Frontier / leaf detector
**Status:** New

Responsibility:

- compute which unresolved scaffold nodes are current leaves.

Why it is needed:

- Step 4 of the workflow depends on a precise frontier.

Relationship to existing code:

- `informalize deps` is helpful at declaration granularity, but we need node-level frontier logic.

#### 16. Readiness evaluator
**Status:** New

Responsibility:

- classify a frontier node as ready, needing sources, needing refinement, or blocked.

Inputs:

- scaffold node,
- knowledge store,
- dependency state,
- local Lean context when relevant.

Why it is needed:

- this is the branching decision point of the workflow.

#### 17. Scaffold refinement engine
**Status:** New

Responsibility:

- replace a coarse node with a more detailed local sub-scaffold.

Typical refinements:

- introduce auxiliary lemmas,
- split definitions from proofs,
- expose hidden prerequisites,
- break large nodes into case-based or structural subnodes.

Why it is needed:

- not-ready nodes often need decomposition rather than immediate formalization.

#### 18. Scaffold state updater
**Status:** New

Responsibility:

- update node statuses and dependencies after refinement or successful formalization.

Why it is needed:

- the frontier must be recomputed from an accurate current scaffold state.

---

### D. Source-gap and acquisition layer

#### 19. Source-gap detector
**Status:** New

Responsibility:

- determine what source support is missing for a node.

Typical missing items:

- precise statement variants,
- proof hints,
- notation mappings,
- prerequisite lemmas,
- prior formal analogues.

Why it is needed:

- Step 6a requires more than just “not enough information”; it requires a concrete diagnosis of what is missing.

#### 20. Source acquisition planner
**Status:** New

Responsibility:

- decide where to look for additional material once a gap has been identified.

Outputs:

- target queries,
- candidate repositories/documents,
- acquisition priorities.

Why it is needed:

- gathering more sources should be systematic, not ad hoc.

#### 21. Source-incorporation loop
**Status:** New

Responsibility:

- send newly found sources back through ingestion and into the knowledge store.

Why it is needed:

- the workflow requires new sources to become first-class knowledge-store content before they are relied on.

---

### E. Formalization-execution layer

#### 22. Formalization task builder
**Status:** New

Responsibility:

- package a ready scaffold node into a concrete Lean task.

Inputs should include:

- node description,
- relevant source-backed knowledge,
- nearby scaffold context,
- Lean file/declaration target.

Why it is needed:

- the agent needs a crisp local task before entering the AFTK-assisted formalization phase.

#### 23. Lean workspace manager
**Status:** New

Responsibility:

- manage the file/module context in which the formalization will be attempted.

Why it is needed:

- the orchestration layer should know where edits occur, which files need reloading, and when verification should run.

#### 24. AFTK integration adapter
**Status:** Partial

Responsibility:

- connect the formalization task builder and orchestrator to the existing AFTK tool surface.

Why it is needed:

- AFTK already exists, but the larger workflow still needs a component that decides when and how to use it.

#### 25. Formalization executor
**Status:** New

Responsibility:

- carry out the actual formalization attempt for a ready node.

Typical actions:

- query AFTK hover/goals,
- explore tactics transiently,
- write final Lean code,
- collect errors or evidence for fallback decisions.

Why it is needed:

- this is the component that converts “ready” into real Lean code.

#### 26. Verification / acceptance gate
**Status:** New

Responsibility:

- determine whether a formalization attempt is accepted.

Checks may include:

- Lean elaboration success,
- project build success,
- test success where relevant,
- replacement of the intended informal node.

Why it is needed:

- the workflow should not mark nodes formalized merely because a draft proof was generated.

#### 27. Node replacement and code-update component
**Status:** New

Responsibility:

- replace the relevant informal placeholder with verified Lean code and preserve relevant notes/citations.

Why it is needed:

- successful formalization must update both code and scaffold state.

#### 28. Formalization writeback component
**Status:** New

Responsibility:

- add successful formalizations and useful failed-attempt data back into the knowledge store.

Why it is needed:

- later nodes should be able to reuse what earlier nodes learned.

---

### F. Orchestration and memory layer

#### 29. Workflow orchestrator
**Status:** New

Responsibility:

- run the full control loop from `docs/workflow.md`.

Core duties:

- maintain the current project state,
- choose the next frontier node,
- route nodes to readiness assessment, source acquisition, refinement, or formalization,
- repeat until scope completion.

Why it is needed:

- without an orchestrator, the repository only contains useful local tools rather than an end-to-end framework.

#### 30. Prioritization policy / scheduler
**Status:** New

Responsibility:

- choose which frontier node to work on next.

Possible heuristics:

- lowest dependency depth,
- highest unblock value,
- smallest expected formalization cost,
- best source coverage.

Why it is needed:

- the scaffold may have many leaves; we need a principled way to pick among them.

#### 31. Attempt log and decision history
**Status:** New

Responsibility:

- record readiness decisions, failures, source acquisitions, refinements, and successes.

Why it is needed:

- the workflow is iterative and benefits from explicit memory of what already happened.

#### 32. Failure classifier / fallback router
**Status:** New

Responsibility:

- decide whether a failed formalization attempt should lead to more source gathering, more refinement, or a retry with changed tactics.

Why it is needed:

- failure handling is a core part of the loop, not an afterthought.

---

## Cross-cutting requirements

These are not separate user-facing components, but they must be built into the framework.

### Provenance discipline
Everything should stay traceable to source material or to explicit agent-derived reasoning.

### Stable identifiers
Sources, knowledge items, scaffold nodes, and formalization attempts need stable ids for reliable linking.

### Distinction between source-backed and derived content
The knowledge store must never blur these together.

### Incremental updates
The framework should support repeated ingestion, repeated scaffold refinement, and repeated writeback without rebuilding everything from scratch.

### Agent-readable representations
Outputs of each component should be designed for machine consumption, not only for human inspection.

---

## Suggested implementation order

A reasonable development order is:

1. **Source registry + faithful ingester + source-packet storage**
   - because everything else depends on faithful input.

2. **Knowledge store + query/writeback + provenance layer**
   - because the workflow assumes the agent can query and update knowledge at any time.

3. **Scaffold node registry + initial scaffold generator + frontier detector**
   - because we need an explicit object to iterate over.

4. **Readiness evaluator + source-gap detector + refinement engine**
   - because these determine the main branch points of the loop.

5. **Formalization task builder + orchestrator + verification gate**
   - because this turns the current Informalize/AFTK toolset into an actual end-to-end workflow.

6. **Failure routing, prioritization, and richer writeback**
   - because these improve robustness after the basic loop exists.

---

## Minimal viable framework shape

The first implementation does **not** need to be a distributed system or a large service stack.
A good MVP could be file-backed and repository-local:

- source registry as a manifest file,
- ingested source packets as markdown/JSON artifacts,
- knowledge store as JSON or SQLite,
- scaffold registry built around `informal[...]` ids plus metadata,
- orchestrator as an agent-controlled workflow script,
- AFTK and Informalize reused as they already exist.

That would already be enough to validate the workflow before investing in more sophisticated infrastructure.
