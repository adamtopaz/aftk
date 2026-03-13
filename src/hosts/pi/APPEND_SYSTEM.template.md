# AFTK agent guidance

This project uses AFTK for autoformalization and repo-mediated coordination. Treat persistent repo artifacts as both the source of truth and the coordination channel between agents.

## Stigmergic coordination model

- `entrypoint.md` is the top-level task description for the current run. Read it first when present.
- The repo itself is the orchestration layer. Informal nodes, knowledge-base nodes, Lean source, placeholders, and related metadata are not just code or documentation; they are genuine orchestration artifacts.
- Do not assume a hidden task queue, hidden coordinator, or chat-only shared memory outside the repo.
- Work stigmergically: agents coordinate by reading and writing durable repo state.
- If a discovery, decomposition, or next-step matters for future work, encode it in the repo rather than leaving it only in chat.

## Available tool families

- Lean/server tools: open Lean files, inspect hover/goals/term goals/infoview, load tactic nodes, and run transient tactic exploration.
- Knowledge-base tools: inspect, search, validate, and relate knowledge-base nodes.
- Informal tools: inspect tracked declarations/references/dependencies and render knowledge-base-backed presentation.

## Start-of-turn workflow

1. Read `entrypoint.md` and any directly referenced source material.
2. Inspect the current project state before editing. On large projects, stay selective and use the cheapest high-value queries first.
3. Use informal and knowledge-base tools to locate the relevant frontier: leaf references, dependency leaves, tracked declarations, node relationships, and nearby notes.
4. Only after locating the frontier should you open Lean files, inspect goals, or explore tactics.
5. Choose one concrete chunk of work for this turn. Do not try to complete all of `entrypoint.md` in a single response.
6. Make the chosen change, re-check, and leave the repo in a clearer state for the next agent.

If `entrypoint.md` is missing, say so briefly and fall back to the best local orchestration artifacts already present in the repo.

## Context-budget discipline

- Prefer targeted queries over broad file dumps.
- For large projects, start from leaves, boundaries, bottlenecks, or lightly connected frontiers.
- A good pattern is: inspect leaf informal references or dependency leaves, inspect the corresponding knowledge-base nodes, then inspect only the Lean declarations and source spans needed for the chosen subtask.
- Expand scope only when the current evidence says it is necessary.

## What counts as meaningful progress in one turn?

Meaningful progress is not only “finish the theorem.” Good single-turn contributions include:

- split an overloaded informal node into multiple smaller informal nodes with clearer roles
- split a large knowledge-base node into smaller nodes with explicit relationships
- create missing leaf nodes or subproblems discovered from `entrypoint.md`
- tighten node titles, summaries, metadata, tags, and relationships so search and navigation improve
- connect Lean declarations to the correct informal or knowledge-base references
- replace a vague placeholder with a sharper local lemma, proof skeleton, or better-scoped TODO
- formalize one well-chosen leaf or lemma instead of attacking a whole cluster at once
- record the next frontier in durable repo artifacts when full formalization is premature

Prefer changes that reduce ambiguity, reduce task size, and improve resumability for later agents.

## Lean-state workflow

- Use knowledge-base and informal tools to understand existing structure before inventing new structure.
- Use Lean/server tools only after identifying the exact file, declaration, or proof location of interest.
- Use transient tactic exploration to test candidate proof steps.
- Only after a tactic branch works should you write corresponding Lean source edits and re-check.

## Safety rules

- `load_node`, `run_tactic`, and `run_tactic_steps` operate on transient tactic-state nodes, not persisted proof edits.
- Do not treat a successful transient tactic branch as committed proof text until you write it into Lean source and re-check.
- Canonical prose and orchestration metadata live in the knowledge base and related repo artifacts.
- The informal layer is the Lean-facing bridge to that knowledge.
- Prefer inspecting actual AFTK state through tools over inventing assumptions.
- Prefer leaving important coordination information in persistent repo artifacts, not only in chat.
