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

## Tool-choice policy

- Prefer `informal_*` and `knowledgebase_*` queries over ad hoc file searches when you need to understand declaration references, dependency leaves, node bodies, metadata, relationships, or presentation.
- Prefer `aftk_*` Lean/server queries over raw source inspection when you need hover, goals, term goals, tactic-state nodes, or proof-state feedback.
- Do not treat the informal and knowledge-base layers as read-only. After using their queries to locate the frontier, be willing to create, split, refine, or connect the corresponding repo artifacts directly when that is the best next step.
- Use built-in file tools (`read`, `bash`, `edit`, `write`) for surrounding repository work, precise source edits, and direct edits to knowledge-base / informal artifacts not covered by AFTK mutation tools — not as the default replacement for AFTK queries.
- Avoid starting with broad `grep`, `find`, or large file dumps if an AFTK query can narrow the frontier first.
- A strong default sequence is: `informal_*` / `knowledgebase_*` to locate the frontier, then targeted `aftk_*` inspection as needed, then direct repo edits that improve Lean, informal, or knowledge-base state around the exact frontier you now understand.

## Start-of-turn workflow

1. Read `entrypoint.md` and any directly referenced source material.
2. Before using generic repo search, ask whether an `informal_*`, `knowledgebase_*`, or `aftk_*` query can answer the question more directly.
3. Inspect the current project state before editing. On large projects, stay selective and use the cheapest high-value AFTK queries first.
4. Use informal and knowledge-base tools to locate the relevant frontier: leaf references, dependency leaves, tracked declarations, node relationships, and nearby notes.
5. Only after locating the frontier should you open Lean files, inspect goals, or explore tactics.
6. Choose one concrete chunk of work for this turn. Do not try to complete all of `entrypoint.md` in a single response.
7. Make the chosen change, re-check, and leave the repo in a clearer state for the next agent.

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
- create missing leaf nodes, subproblems, or coordination notes discovered from `entrypoint.md`
- tighten node titles, summaries, metadata, tags, and relationships so search and navigation improve
- connect Lean declarations to the correct informal or knowledge-base references
- add or refine knowledge-base / informal content directly in the repo when that sharpens the frontier better than pushing immediately on proof text
- replace a vague placeholder with a sharper local lemma, proof skeleton, or better-scoped TODO
- formalize one well-chosen leaf or lemma instead of attacking a whole cluster at once
- record the next frontier in durable repo artifacts when full formalization is premature

Prefer changes that reduce ambiguity, reduce task size, and improve resumability for later agents.

## Lean-state workflow

- Use knowledge-base and informal tools to understand existing structure before inventing new structure.
- Use Lean/server tools only after identifying the exact file, declaration, or proof location of interest.
- Prefer `aftk_get_hover`, `aftk_get_plain_goal`, `aftk_get_plain_term_goal`, `aftk_get_infoview`, and `aftk_get_goals` over reading Lean files when your real question is about Lean state rather than surface text.
- Use transient tactic exploration to test candidate proof steps.
- Only after a tactic branch works should you write corresponding Lean source edits and re-check.

## Common anti-patterns

- Do not begin by dumping large Lean files when `informal_*`, `knowledgebase_*`, or targeted `aftk_*` queries can narrow the problem first.
- Do not use broad repo search to discover informal references or dependency frontiers before checking the informal and knowledge-base tool families.
- Do not inspect proof state indirectly through source text when the Lean/server tools can query Lean directly.
- Do not treat a successful transient tactic branch as committed proof text until you write it into Lean source and re-check.

## Safety rules

- `load_node`, `run_tactic`, and `run_tactic_steps` operate on transient tactic-state nodes, not persisted proof edits.
- Do not treat a successful transient tactic branch as committed proof text until you write it into Lean source and re-check.
- Canonical prose and orchestration metadata live in the knowledge base and related repo artifacts.
- The informal layer is the Lean-facing bridge to that knowledge.
- Prefer inspecting actual AFTK state through tools over inventing assumptions.
- Prefer leaving important coordination information in persistent repo artifacts, not only in chat.
