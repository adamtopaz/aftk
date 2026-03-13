# Plan: scalable orchestration framework for autoformalization

## Goal

Build the first real orchestration framework for AFTK around two agent roles:

- an **orchestrator agent**
- a **worker agent**

while keeping the long-term target in view:

> a massively scalable autoformalization system that can process multiple textbooks and research papers, with deep and nontrivial dependencies between them, and turn natural-language mathematics into Lean 4 artifacts.

The key point is that the first prototype should not paint us into a corner.
It should already reflect the structure we will need when the system stops being a single-run demo and starts becoming a large, persistent, multi-corpus workflow.

---

## What I reviewed

I reviewed the current state of the repository in the parts most relevant to orchestration and future scaling:

- top-level architecture and roadmap:
  - `README.md`
  - `docs/architecture.md`
  - `docs/roadmap.md`
- existing planning docs:
  - `plans/tasks.md`
  - `plans/orchestration.md`
  - `plans/task_toolkit.md`
  - `plans/orchestrator_toolkit.md`
- current task/orchestration substrate:
  - `aftk/tasks/models.py`
  - `aftk/tasks/graph.py`
  - `aftk/tasks/store.py`
  - `aftk/tasks/manager.py`
  - `aftk/tasks/planner.py`
  - `aftk/tasks/prompts.py`
  - `aftk/tasks/proposals.py`
  - `aftk/tasks/workers.py`
- current agent-facing tool surfaces:
  - `aftk/toolkits/tasks/_toolkit.py`
  - `aftk/toolkits/tasks/models.py`
  - `aftk/toolkits/orchestrator/_toolkit.py`
  - `aftk/toolkits/orchestrator/models.py`
- relevant tests:
  - `tests/python/test_task_manager.py`
  - `tests/python/test_task_orchestration.py`
  - `tests/python/test_task_toolkit.py`
  - `tests/python/test_orchestrator_toolkit.py`
  - `tests/python/test_task_planner.py`
- semantic substrate that the framework will rely on:
  - `docs/knowledgebase/overview.md`
  - `docs/informal/overview.md`
  - `docs/server/overview.md`
  - `AFTK/KnowledgeBase/Search.lean`
  - `AFTK/Informal/Dependencies.lean`

---

## Current state of the repo

The repo is no longer at zero. A substantial part of the orchestration substrate already exists.

## What is already in good shape

### 1. Semantic foundation

The core AFTK stack is already implemented and usable:

- **knowledge base** as canonical prose storage
- **informal layer** as the Lean-facing bridge to knowledge-base references
- **Lean server / file-worker layer** for Lean queries and tactic exploration
- **Python client** plus reusable Pydantic AI toolkits

This is important because it means the future framework does **not** need to invent its own semantic backend.
It should sit on top of this stack.

### 2. Operational task substrate

The Python task layer already provides:

- explicit task/run/attempt/artifact models
- dependency validation and cycle detection
- derived scheduler status (`ready`, `blocked`, etc.)
- a file-backed and in-memory store abstraction
- `TaskManager` as the central authority for state transitions
- simple orchestration helpers for executing ready tasks
- planner helpers derived from informal dependency views

This is already a real orchestration core for a prototype.

### 3. Role-separated toolkits

The repo already implements the key role boundary we need:

- `TaskToolkit` for **worker-safe** task interaction
- `OrchestratorToolkit` for **global workflow control**

These are not just plans anymore; they already exist in code, along with tests.
That is a strong starting point.

### 4. Proposal and dispatch seams

The repo already has:

- structured worker task proposals in `aftk/tasks/proposals.py`
- a `TaskWorkerRunner` protocol in `aftk/tasks/workers.py`
- orchestrator-side proposal review/apply tools
- orchestrator-side dispatch tools that can drive an injected worker runner

So the next step is **not** to invent the authority model from scratch.
The next step is to turn this substrate into a real framework.

---

## What is still missing

Despite that progress, the current state is still a prototype substrate rather than a full framework.

The biggest missing pieces are:

1. **No actual orchestrator-agent runtime**
   - there is an orchestrator toolkit, but not yet a concrete orchestrator agent profile/runtime
2. **No actual worker-agent runtime**
   - there is a worker toolkit and a worker-runner protocol, but not yet a concrete worker agent implementation
3. **No framework-level control plane**
   - no durable scheduler service, no lease model, no event log, no indexed ready queue
4. **No multi-corpus planning model**
   - current tasks are run-local and generic, not yet tied to an explicit corpus/document/shard architecture
5. **No stable semantic/work split at framework level**
   - tasks exist, but there is not yet a separate long-lived graph of corpus units, formal targets, and reusable interfaces
6. **No hierarchical orchestration model**
   - today the natural default is one orchestrator loop; that will not scale to many books and papers
7. **No large-scale invalidation/reuse story**
   - current task runs are resumable, but not yet designed for massive incremental recomputation across evolving corpora

---

## Main architectural conclusion

The correct next step is:

> build a new **framework layer above the current task/toolkit substrate**, not a replacement for it.

More concretely:

- keep `aftk.tasks` as the task-domain foundation
- keep `TaskManager` as the task-state authority
- keep `TaskToolkit` and `OrchestratorToolkit` as the role boundary
- add a new framework/runtime layer that turns those pieces into real agents and a real orchestration loop

That framework layer should be designed from day one with **multi-corpus**, **multi-shard**, and eventually **multi-worker** execution in mind.

---

## Core scaling insight

For massive scale, the orchestrator agent cannot itself be the whole system.

A single smart orchestrator agent may be acceptable for a prototype, but it cannot become the sole location of:

- task storage
- dependency computation
- dispatch ordering
- retry policy
- run bookkeeping
- proposal review
- cross-document dependency reconciliation

At scale, those must live mostly in **deterministic infrastructure**.
The agent should sit on top of that infrastructure as a planner/reviewer/exception-handler.

So the right mental model is:

- **framework/control plane**: deterministic, durable, scalable
- **agents**: bounded decision-makers operating over summaries, proposals, and local task context

This matters immediately, because it changes how we should design the prototype.
The prototype should already have the right seams.

---

## Architectural principles for the framework

## 1. Python owns orchestration

This remains the right top-level choice.

- tasks, runs, retries, leases, and scheduling are workflow concerns
- agents already live in Python
- Lean should remain the semantic backend, not the workflow runtime

## 2. Lean/AFTK remains the semantic substrate

The framework should reuse the current AFTK stack for:

- knowledge-base facts and relationships
- informal reference/declaration dependency views
- Lean editor-style queries
- build/repair/validation context

The framework should avoid bypassing the server/client boundary unless a concrete missing query forces a narrow extension.

## 3. Separate **stable semantic graphs** from **run-local task graphs**

This is the most important framework-level addition.

Tasks are operational.
They are not the whole system.

For large-scale autoformalization we need at least two distinct layers:

1. **stable semantic/work subjects**
   - corpus
   - document
   - section/span/unit
   - knowledge-base node
   - Lean module/declaration/formal target
2. **run-local operational tasks**
   - draft
   - repair
   - validate
   - review
   - requeue
   - dispatch

If we treat tasks as the only graph, we will eventually lose:

- reuse across runs
- stable provenance
- cross-document planning clarity
- clean invalidation semantics

## 4. Make context bounded and interface-driven

Workers must not depend on global monolithic context.
For scale, they need:

- a small task context
- dependency summaries
- local source/formal artifacts
- imported interface artifacts from upstream shards

That means the framework should eventually plan around **interfaces**, not only around raw transitive closure.

## 5. Keep authority boundaries hard

The current repo already made the right move here:

- workers get worker-safe tools
- orchestrators get global-control tools

The framework should preserve and deepen that split.
Do not collapse it by letting worker profiles quietly become mini-orchestrators.

## 6. Design for hierarchical orchestration

Eventually we will need more than one orchestrator layer.
A plausible long-term shape is:

- **global orchestrator** for portfolio/corpus planning
- **shard orchestrators** for document/module/chapter-level work
- **workers** for bounded execution tasks

The first implementation can be flat, but the framework should not assume flatness forever.

## 7. Prefer idempotent, replayable worker tasks

At scale, workers fail, time out, and get retried.
So worker tasks should be designed to be:

- bounded in scope
- explicit about inputs
- artifact-producing
- replayable
- easy to validate after the fact

## 8. Capture provenance from the start

Every meaningful artifact should eventually be traceable back to:

- source corpus/document/unit
- upstream dependencies
- task/attempt history
- agent decisions and proposals
- Lean validation outcomes

This is essential for debugging, evaluation, and human review.

---

## Framework model

The framework should be understood as four layers sitting above the existing semantic substrate.

## Layer 0: semantic substrate (already implemented)

Owned mostly by the current codebase:

- knowledge base
- informal layer
- Lean server/file worker
- Python client/toolkits

## Layer 1: subject graph

New framework concept.
This should represent the long-lived semantic/work units the system cares about, such as:

- `corpus_id`
- `document_id`
- `source_unit_id` (section, theorem statement, proof paragraph, etc.)
- `knowledge_node_id`
- `formal_target_id` (Lean module/declaration target)
- interface/export artifacts for shards

This layer should be more stable than task runs.

## Layer 2: task graph

Built on top of the existing `aftk.tasks` layer.
Tasks are run-local work items against subjects, for example:

- extract structure from a source unit
- align a source unit to a KB node
- draft a Lean declaration
- repair a build error
- validate a completed formalization
- review a worker proposal

## Layer 3: control plane

New framework concept.
This is the durable execution/runtime layer that should eventually own:

- ready-queue selection
- claim/lease semantics
- retries and retry policy
- artifact/event persistence
- worker dispatch
- operator summaries and observability

In the first prototype, this can still be local and simple.
But the interfaces should be chosen so that it can grow.

## Layer 4: agent plane

This is where the actual orchestrator and worker agents live.
They should be implemented as profiles over the lower layers, not as ad hoc scripts.

---

## Recommended roles

## Worker agent

The worker agent should be optimized for:

- performing one bounded task
- consulting coding and AFTK tools
- recording notes/artifacts
- proposing follow-up tasks

The worker agent should not own global workflow state.

### Immediate worker profile

The initial worker profile should likely compose:

- `CodingToolkit`
- `AftkToolkit`
- `TaskToolkit(current_task_id=...)`

wrapped behind a concrete `TaskWorkerRunner` implementation.

### Long-term worker direction

Over time we will likely want multiple worker profiles by task kind, for example:

- extraction worker
- context-gathering worker
- formalization worker
- repair worker
- validation/review worker

The framework should therefore introduce the notion of a **worker profile registry**, even if v1 only has one default worker.

## Orchestrator agent

The orchestrator agent should be optimized for:

- inspecting run-wide state
- refining tasks and dependencies
- reviewing worker proposals
- deciding priorities and retries
- handling exception paths
- selecting when worker execution should happen

### Immediate orchestrator profile

The initial orchestrator profile should likely compose:

- `CodingToolkit`
- `AftkToolkit`
- `OrchestratorToolkit`

### Long-term orchestrator direction

At scale, the orchestrator agent should not be expected to manually shepherd every single ready task.
Instead it should increasingly focus on:

- planning
- exception handling
- review
- policy decisions
- shard/interface coordination

---

## Immediate framework plan

## Phase 1: implement concrete agent profiles and local runners

This is the most immediate next step.
The toolkits already exist; now we should implement actual agents and runners on top of them.

### Deliverables

Create a new framework/orchestration package, likely something like:

```text
aftk/orchestration/
  __init__.py
  models.py
  prompts.py
  worker_agent.py
  orchestrator_agent.py
  runtime.py
  scheduler.py
```

Initial responsibilities:

- `worker_agent.py`
  - concrete worker-agent construction
  - worker prompt/context rendering
  - normalization into `TaskExecutionResult`
- `orchestrator_agent.py`
  - concrete orchestrator-agent construction
  - orchestrator prompt/context rendering
  - one-step decision/execution helpers
- `runtime.py`
  - local orchestration loop built above `TaskManager`
  - dispatch orchestration using current toolkits and `TaskWorkerRunner`
- `scheduler.py`
  - deterministic ready-task ordering/policy helpers

### Important design choice

Do **not** bypass the current task toolkits.
The concrete agents should use the already-implemented authority boundaries.

### Phase 1 success criteria

- we can instantiate a real worker agent for one task
- we can instantiate a real orchestrator agent over a run
- the orchestrator can dispatch a worker through a concrete `TaskWorkerRunner`
- worker proposals flow back through the current proposal/review system
- the whole thing works in a local single-process prototype

---

## Phase 2: add a deterministic orchestration runtime around the agents

The next step is to make the runtime more explicit.

### Why

Even in the prototype, we should avoid turning the orchestrator into an opaque free-form chat loop.
We want a deterministic runtime that decides:

- when to call the orchestrator
- when to dispatch a worker automatically
- when to stop
- when to retry
- when to escalate for review

### Deliverables

Add runtime concepts such as:

- `OrchestrationRun`
- `DispatchPolicy`
- `RetryPolicy`
- `StopCondition`
- run journal / event log / operator summary

The first version can still use the current local file-backed task state, but it should begin separating:

- framework runtime state
- task state
- artifacts/logging

### Phase 2 success criteria

- a run can be resumed cleanly after interruption
- the runtime can produce a stable operator-readable summary of what happened
- worker dispatch is not just an ad hoc helper call but part of a real orchestration loop

---

## Phase 3: define a domain task taxonomy for autoformalization

Right now the task layer is intentionally generic.
That was the right first step.
Now the framework needs a more explicit autoformalization vocabulary.

### Recommended task families

At minimum, the framework should support task kinds like:

- `ingest_source_unit`
- `extract_claims`
- `normalize_terminology`
- `align_to_knowledge_node`
- `create_formal_target`
- `draft_lean_artifact`
- `repair_lean_failure`
- `validate_formalization`
- `review_result`
- `synthesize_interface`

### Why this matters

Massive-scale orchestration depends on task kind semantics.
We will need to know, for example:

- which tasks are cheap and parallelizable
- which tasks produce reusable interface artifacts
- which tasks need stronger validation
- which tasks are safe to retry automatically

### Phase 3 success criteria

- task payloads carry stable subject references, not just ad hoc JSON
- the worker-profile registry can choose defaults by task kind
- the orchestrator can reason over task classes, not only task ids

---

## Phase 4: add a subject graph and shard model for multi-document scaling

This is the phase where the framework starts being genuinely designed for many books and papers.

### Key idea

We should not orchestrate directly at the level of “one giant pile of tasks for the whole library”.
We need explicit shardable units.

### Recommended shard candidates

Possible shard boundaries include:

- corpus
- document
- chapter/section
- Lean module
- semantic SCC/component

The exact boundary can vary, but the framework should make it explicit.

### Interface-first planning

Each shard should eventually publish interface artifacts such as:

- normalized definitions it exports
- theorem statements it claims to provide
- required upstream concepts/results
- mapped Lean declaration targets
- unresolved obligations

Cross-shard dependencies should preferentially flow through these interfaces.

### Why this matters

This is how we avoid requiring every worker or orchestrator to load the entire mathematical universe into context.

### Phase 4 success criteria

- tasks can be attached to explicit shards
- shard boundaries and cross-shard edges are visible in the framework
- the planner can schedule many documents/modules with bounded context and explicit dependencies

---

## Phase 5: evolve the storage and execution model for concurrency

The current JSON snapshot + single-writer model is excellent for a prototype.
It is not the end state for a massive system.

### What will eventually be needed

- indexed task/run queries
- lease/heartbeat semantics for worker claims
- crash-safe resumption
- separation of task state from large artifacts/logs
- fast ready-queue lookup
- support for many concurrent workers
- event history suitable for audit/debugging

### Recommended direction

Keep `TaskManager` as the semantic authority for transitions, but evolve the storage layer behind it.
Likely we will eventually want to separate:

- state store
- artifact/blob store
- event log
- queue/index structures

### Important note

This does **not** need to be implemented immediately.
But the framework should avoid assuming that a single in-memory or single-file snapshot is permanent.

### Phase 5 success criteria

- multiple workers can claim and complete work safely
- orchestration survives crashes cleanly
- the framework is no longer serialized around one local process

---

## Phase 6: add validation, provenance, and incremental recomputation

Large-scale autoformalization will only be useful if it is inspectable and restartable.

### Required capabilities

- artifact provenance back to source units and task attempts
- Lean build/test validation checkpoints
- failure classification
- invalidation when upstream semantic subjects change
- reuse of completed artifacts when inputs have not changed
- operator visibility into quality and throughput

### Why this matters

With many books and papers, the central problem is not only generating outputs.
It is keeping the system coherent as new material arrives, earlier artifacts are refined, and dependencies shift.

### Phase 6 success criteria

- changing one upstream source/formal target only invalidates the relevant downstream slices
- operators can inspect why an artifact exists and what evidence supports it
- evaluation can be run over benchmark corpora reproducibly

---

## Specific design decisions to make now

These decisions should be made early because they shape everything else.

### 1. Stable subject identifiers

From the start, task payloads should refer to explicit stable subjects such as:

- corpus id
- document id
- source unit id
- knowledge node id
- formal target id

Even if the first implementation only uses a subset of these, the framework should not stay purely anonymous.

### 2. Task ids should remain operational

Task ids may be stable within a run, but they should not be the only identity mechanism.
The durable identity should live in the subject references inside task payload/metadata.

### 3. Keep proposal/review flow explicit

The current worker-proposal and orchestrator-review design is correct and should remain central.
At scale, this is how we preserve auditability and control over graph growth.

### 4. Introduce a worker-profile registry early

Even if v1 only has one worker profile, the framework should be built so it can later route different task kinds to different worker profiles.

### 5. Do not make `orch_dispatch_next_ready` the long-term architecture

It is a fine prototype mechanism.
It is not a sufficient large-scale control plane.
Long-term dispatch must become more policy-driven and less dependent on one serial agent loop.

### 6. Treat shard interfaces as first-class future artifacts

When scaling across textbooks and papers, interfaces are how we keep context bounded and recomputation manageable.
We should plan for them now, even if they arrive in a later phase.

---

## Recommended first deliverable

The best first concrete framework milestone is:

1. implement a concrete **worker agent runner** on top of:
   - `CodingToolkit`
   - `AftkToolkit`
   - `TaskToolkit`
2. implement a concrete **orchestrator agent runner** on top of:
   - `CodingToolkit`
   - `AftkToolkit`
   - `OrchestratorToolkit`
3. implement a small **local orchestration runtime** that:
   - loads a run
   - asks the orchestrator to inspect and refine state when needed
   - dispatches workers through a concrete `TaskWorkerRunner`
   - records notes, artifacts, proposals, and final task outcomes
4. test this on a small dependency chain seeded from existing task specs or informal dependency-derived specs

### Why this is the right first slice

It uses the substrate that already exists.
It proves the actual agent/runtime architecture.
And it still leaves a clean path toward:

- worker specialization
- shard-based planning
- scalable storage
- distributed execution

---

## Open questions

These do not block the first framework slice, but they should stay visible.

1. **What is the right first subject model?**
   - knowledge-base nodes only?
   - document sections/spans too?
   - Lean targets too?

2. **Where should shard boundaries live first?**
   - per document?
   - per chapter?
   - per Lean module?

3. **How much graph mutation should the orchestrator agent do directly?**
   - full planning?
   - proposal review only?
   - deterministic planner with agent review?

4. **When should we move beyond JSON snapshot state?**
   - immediately after the first local runtime?
   - only when we introduce multi-worker concurrency?

5. **What should interface artifacts contain first?**
   - only theorem/definition summaries?
   - also Lean target mappings and open obligations?

6. **How should we combine dependency sources?**
   - source/document structure
   - KB relationships
   - informal reference dependencies
   - Lean declaration dependencies

---

## Summary

The repo already contains a strong prototype substrate for orchestration:

- task/run models
- `TaskManager`
- worker-safe and orchestrator-safe toolkits
- proposal flow
- worker-runner seam

So the next step is not to redesign the authority model.
It is to build the actual **framework layer** on top of it.

The crucial scaling lesson is:

> the orchestrator agent should be part of the framework, not the whole framework.

A scalable system will need:

- deterministic control-plane infrastructure
- stable semantic subject identities
- run-local task graphs layered on top of those subjects
- bounded worker context
- explicit shard/interface boundaries
- durable provenance and incremental recomputation

So the immediate implementation target should be:

- concrete orchestrator and worker agents
- a local orchestration runtime above the existing task/toolkit layer
- APIs and data shapes that already point toward hierarchical, multi-corpus scaling later
