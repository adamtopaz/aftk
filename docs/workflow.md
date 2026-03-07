# Autoformalization Workflow

This document defines the intended end-to-end workflow for building autoformalization projects on top of the current AFTK repository.

The repository already gives us three key building blocks:

- **Informalize** for scaffold placeholders (`informal[...]`) and markdown-backed blueprint notes.
- **AFTK knowledge-base CLI** for repository-local sources, packets, knowledge entries, and provenance.
- **AFTK hub tools** for Lean semantic queries and transient tactic exploration during local formalization work.

What is still missing is the larger orchestration layer that starts from source material, improves ingestion/extraction quality, constructs/refines a scaffold graph more explicitly, and then drives formalization to completion. This document makes that larger loop precise.

See also:

- `docs/components.md` for the framework pieces needed to implement this workflow.
- `docs/informalize/README.md` for the current scaffold/blueprint layer.
- `docs/aftk/README.md` for the current Lean-facing tool layer.

In this document, **knowledge store** and **knowledge base** mean the same evolving, source-linked repository of reusable project knowledge.

---

## Core principles

1. **Source-first**
   - Every scaffold node and every formalization attempt should be traceable to source material or to an explicit refinement decision derived from source material.

2. **Faithful ingestion**
   - Ingestion may normalize formatting, but it must not silently paraphrase away structure or provenance.
   - The agent should be able to recover where a statement came from, what section it was in, and what nearby context it originally had.

3. **Scaffold before full formalization**
   - We do not aim for one-shot formalization.
   - We first build an explicit scaffold of informal nodes and then formalize leaves incrementally.

4. **Leaf-first refinement**
   - At each iteration, the agent should work on unresolved leaf nodes of the current scaffold.
   - A node is either formalized, refined into smaller children, or supported by new source material.

5. **Knowledge store is always available**
   - At any point, the agent may query the knowledge store or add new material to it.
   - The store must distinguish source-backed knowledge from agent-derived notes or hypotheses.

6. **AFTK is a local formalization accelerator**
   - AFTK is used when the agent is actively formalizing a selected node.
   - Its transient tactic states are exploration tools, not final artifacts.

---

## Main artifacts

### 1. Source record
A raw source input together with metadata.

Minimum contents:

- stable source id,
- source kind (paper, textbook chapter, notes, prior formalization, etc.),
- location or URI,
- version/hash when available,
- licensing/access notes when relevant.

### 2. Source packet
A faithful, agent-readable representation of a source record.

Minimum contents:

- normalized text,
- structural anchors (section, subsection, theorem label, page, equation label, etc.),
- chunk boundaries,
- provenance links back to the raw source,
- optional extracted math structure already recognized during ingestion.

### 3. Knowledge store entry
A retrievable item derived from one or more source packets.

Typical entry kinds:

- definitions,
- theorem statements,
- proof sketches,
- notation conventions,
- examples/counterexamples,
- dependency hints,
- agent-authored planning notes,
- formalization outcomes.

Every entry should carry:

- a stable id,
- type/classification,
- provenance,
- links to related entries,
- source-backed vs derived status.

### 4. Scaffold node
A node in the current informal formalization plan.

Minimum contents:

- stable node id,
- natural-language intent,
- target Lean location or declaration context,
- links to source and knowledge-store entries,
- child dependencies,
- current status.

In the current repository, the natural anchor for these nodes is `informal[...]` plus the associated markdown file under `informal/`.

### 5. Formalization artifact
The Lean code that replaces an informal node once it has been formalized.

Minimum contents:

- Lean declaration text or proof term/tactic script,
- links to the scaffold node it replaced,
- supporting source/knowledge citations,
- verification result.

### 6. Attempt log
A record of what the agent tried.

This includes:

- readiness decisions,
- missing-information diagnoses,
- refinement decisions,
- AFTK tactic exploration results,
- verification failures,
- eventual success criteria.

---

## Node lifecycle

A scaffold node should move through statuses like the following:

- `scaffolded` — node exists but has not yet been assessed.
- `needs_sources` — the node cannot yet be formalized because source support is missing or insufficient.
- `needs_refinement` — the node is too coarse, ambiguous, or large; it should be split into child nodes.
- `ready` — the node is a leaf and appears ready for direct formalization.
- `formalizing` — the agent is currently working on it in Lean.
- `formalized` — the node has been replaced by Lean code and verified.
- `blocked` — the node cannot currently progress for a known reason that should be surfaced explicitly.

These are workflow states, not necessarily current implementation details.

---

## Precise workflow

### 0. Select scope and seed sources

Input:

- an initial autoformalization target,
- one or more seed sources meant to support that target.

Actions:

- decide the scope of the current project slice,
- register the initial source set,
- identify whether the project is building from informal mathematical text, an existing blueprint, a prior formalization, or a mixture.

Output:

- a project scope definition,
- a seed source set ready for ingestion.

Exit condition:

- the project has at least one registered source record and a clear target boundary.

---

### 1. Ingest source material into a faithful agent-readable representation

Input:

- one or more raw source records.

Actions:

- convert each source into normalized text or another machine-readable form,
- preserve structural information such as section boundaries, theorem names, definitions, examples, and page or label anchors,
- split the source into chunks that are useful for retrieval,
- attach provenance so each chunk can be traced back to the original source,
- avoid unsupported rewriting: normalization is allowed, silent reinterpretation is not.

Output:

- source packets that the agent can read directly.

Exit condition:

- the agent can retrieve source content together with enough metadata to cite where it came from.

Notes:

- Today, the repository supports repository-local packet persistence through `lake exe aftk packet ingest ...`, but richer document normalization still needs to be built on top of it.
- This step is about faithful representation, not yet about formalization.
- If a source is low quality or incomplete, that should be represented explicitly rather than hidden.

---

### 2. Build or update the knowledge store

Input:

- source packets from Step 1.

Actions:

- extract reusable mathematical content from the source packets,
- create knowledge entries for statements, definitions, notation, examples, and proof ideas,
- store links among entries,
- preserve provenance to the underlying source packets,
- index the store for retrieval by topic, identifier, dependency, and textual query,
- allow the agent to add derived notes, but mark them as derived rather than source-backed.

Output:

- a knowledge store covering the currently ingested source set.

Exit condition:

- the agent can query the knowledge store for facts, notation, explanations, and provenance relevant to the current target.

Operational rule:

- The knowledge store remains mutable for the entire project. The agent may query it or add to it at any stage.

Current-project mapping:

- `lake exe aftk source ...` manages source records.
- `lake exe aftk packet ...` manages source packets and their markdown bodies.
- `lake exe aftk kb ...` manages knowledge entries, provenance, links, scaffold refs, and query/writeback.

---

### 3. Build the initial scaffold with informal nodes

Input:

- the current knowledge store,
- the project target.

Actions:

- decompose the target into an initial graph of informal nodes,
- represent those nodes in Lean using `informal[...]` placeholders where appropriate,
- create markdown notes for each node,
- attach source citations and planning notes to those nodes,
- encode parent/child or prerequisite relationships among nodes,
- keep the scaffold coarse enough to start, but explicit enough that refinement can happen locally.

Output:

- an initial scaffold of unresolved informal nodes.

Exit condition:

- the project has an explicit scaffold that can be traversed and refined.

Current-project mapping:

- `informal[...]`, `informal/.../*.md`, and optional `informal/.../*.json` sidecars are the natural first implementation of scaffold nodes.
- `lake exe informalize ...` provides declaration/location tracking, derived dependency queries, and CLI-managed metadata operations for these placeholders.
- Informalize metadata `knowledgeRefs` can now point at in-repo `kb.*` ids persisted under `aftk-data/knowledge/` and inspectable with `lake exe aftk kb ...`.

---

### 4. Identify the current frontier of leaf informal nodes

Input:

- the current scaffold graph.

Actions:

- compute which nodes are unresolved,
- restrict attention to unresolved leaf nodes,
- prioritize those leaves using dependency position, expected impact, or estimated difficulty.

Definition:

- A **leaf informal node** is an unresolved scaffold node with no unresolved scaffold children.
- In a DAG-shaped scaffold, “leaf” means no outgoing edges to still-unresolved child nodes.

Output:

- a prioritized frontier of candidate nodes for the next iteration.

Exit condition:

- the agent has at least one concrete frontier node to assess.

Note:

- Current `informalize deps` output is a useful starting point at declaration granularity, but the full framework will need explicit scaffold-node frontier tracking.

---

### 5. Assess readiness of each frontier node

Input:

- one frontier node,
- the knowledge store,
- the current scaffold,
- the current Lean dependency context.

Actions:

- determine whether the node statement and scope are precise enough,
- check whether prerequisite concepts and lemmas are already available,
- check whether the relevant supporting source material is already in the knowledge store,
- estimate whether the node is small and local enough for a direct Lean formalization attempt,
- classify the node into one of the workflow outcomes below.

Possible outcomes:

1. **Ready for formalization**
   - The node is precise, adequately sourced, and dependency-ready.

2. **Needs more source material**
   - The node might be formalizable in principle, but the current knowledge store is missing definitions, proof hints, examples, or contextual statements needed to proceed reliably.

3. **Needs refinement**
   - The node is too large, too ambiguous, or conceptually underspecified.
   - It should be replaced by a more detailed local scaffold.

4. **Blocked by unresolved dependencies**
   - The node is not truly ready because one or more prerequisite nodes still need to be formalized first.

Output:

- a readiness classification plus rationale.

Exit condition:

- the agent knows whether to formalize, gather sources, refine, or defer.

---

### 6a. If more source material is needed, locate and ingest it

Input:

- a node classified as `needs_sources`.

Actions:

- identify what is missing: statement variants, definitions, proof details, notation conventions, related lemmas, prior formalizations, etc.,
- locate additional authoritative source material,
- ingest that material using Steps 1 and 2,
- attach the new knowledge to the node and its neighbors,
- re-run readiness assessment.

Output:

- an expanded knowledge store with better support for the node.

Exit condition:

- either the node becomes `ready`, or it still requires refinement or further source work.

Important rule:

- New source material should be incorporated into the knowledge store before it is relied on in later formalization decisions.

---

### 6b. If the node is not yet appropriately shaped, refine the scaffold at that location

Input:

- a node classified as `needs_refinement`.

Actions:

- replace the coarse node by a more detailed local sub-scaffold,
- split the work into smaller child nodes,
- create new informal ids and notes where needed,
- carry forward source citations and open questions,
- update dependencies so future leaf detection sees the new children.

Typical refinement patterns:

- split one theorem into auxiliary lemmas,
- separate a definition step from a proof step,
- isolate notation translation from mathematical argument,
- split existence/uniqueness,
- split by cases or by induction subgoals,
- expose hidden prerequisites as their own nodes.

Output:

- a more detailed scaffold under the same parent location.

Exit condition:

- the original coarse node is replaced by smaller child nodes that can re-enter Step 4.

---

### 7. Formalize a ready leaf node

Input:

- a node classified as `ready`,
- its linked knowledge-store context,
- the current Lean environment.

Actions:

1. gather the node’s local source and knowledge context,
2. open the relevant Lean file and inspect the local state,
3. use AFTK to query hover, goals, term goals, or tactic nodes,
4. attempt a local formalization,
5. use transient AFTK tactic exploration where helpful,
6. write the resulting Lean code explicitly into the file,
7. verify that the result elaborates and fits the surrounding scaffold.

AFTK role in this step:

- `aftk_get_hover` can surface markdown notes attached through Informalize,
- `aftk_load_node`, `aftk_get_goals`, `aftk_run_tactic`, and `aftk_run_tactic_steps` can accelerate local proof search,
- exploratory AFTK node ids are disposable and should not be treated as persistent project state.

Output:

- a candidate Lean formalization replacing the informal node.

Exit condition:

- the node has either been successfully formalized, or the attempt produced enough evidence to send the node back to source gathering or scaffold refinement.

---

### 8. Replace the informal node and update project state

Input:

- a successful formalization attempt.

Actions:

- replace the informal placeholder with the verified Lean code,
- mark the node as `formalized`,
- update parent/neighbor nodes if their readiness changed,
- write back any useful formalization artifacts to the knowledge store,
- preserve the source links and notes that justified the formalization.

Output:

- an updated Lean development and an updated scaffold/knowledge state.

Exit condition:

- the project frontier can be recomputed.

---

### 9. Repeat until all target nodes are formalized

Loop condition:

- continue Steps 4–8 until the scaffold has no unresolved target nodes left.

Project-complete condition:

- all required nodes in scope are formalized,
- the Lean project verifies,
- the resulting formalization remains traceable to its supporting source material.

---

## Readiness checklist for a leaf node

A leaf node should usually be considered **ready** only if all of the following are true:

- the target statement is precise,
- the intended meaning is source-backed,
- notation and definitions are known,
- prerequisite nodes are already formalized or otherwise stable,
- the knowledge store contains the local facts/examples/proof hints needed to attempt formalization,
- the task is small enough to be tackled locally,
- the Lean context needed for the task is understood.

A node should usually be considered **not ready** if any of the following are true:

- the statement is ambiguous,
- hidden sublemmas are still implicit,
- key source support is missing,
- translation from source notation to Lean notation is unsettled,
- the node is too large for a single direct formalization step.

---

## Controller pseudocode

```text
seed_sources := register_initial_sources()
ingest(seed_sources)
update_knowledge_store()
initialize_scaffold()

while unresolved_nodes_exist():
  frontier := prioritized_leaf_nodes()
  node := select_next(frontier)
  decision := assess_readiness(node)

  if decision = needs_sources:
    new_sources := locate_missing_sources(node)
    ingest(new_sources)
    update_knowledge_store()
    continue

  if decision = needs_refinement:
    refine_scaffold_at(node)
    continue

  if decision = blocked_by_dependencies:
    reprioritize(node)
    continue

  attempt := formalize(node, knowledge_store, aftk)

  if attempt.verified:
    replace_node_with_formalization(node, attempt)
    write_back_formalization_knowledge(attempt)
  else:
    record_failure(attempt)
    classify_failure_as_sources_or_refinement(node, attempt)
```

---

## How this maps to the current repository

Today, the repository already supports the following workflow pieces:

- **Scaffold anchors**: `informal[...]` terms, markdown files under `informal/`, and optional metadata sidecars.
- **Scaffold inspection/management**: `lake exe informalize status|deps|decls|decl|locations|location|meta ...`.
- **Repository-local knowledge store**: `lake exe aftk store|source|packet|kb ...` over `aftk-data/`.
- **Lean-local exploration**: AFTK hover/goal/tactic tools, with hover able to surface effective Informalize metadata + notes.

The main missing layers are now the ones above those primitives:

- richer source ingestion / normalization,
- automatic knowledge extraction,
- explicit scaffold-node management beyond current declaration tracking,
- readiness assessment,
- source acquisition,
- automated refinement/orchestration.

Those components are listed in `docs/components.md`.
