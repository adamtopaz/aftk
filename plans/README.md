# Design docs under `plans/`

This directory contains detailed design notes and component plans for `aftk`.
It is **not** the same thing as the implementation docs under `docs/`.

Use the repository docs this way:

- `README.md` — project overview and quick start
- `docs/` — implementation that exists today
- `plan.md` — current roadmap and deferred work
- `plans/` — detailed component plans, design rationale, and some historical research context

## How to read these files

Many files under `plans/` serve two purposes at once:

1. they record the intended architecture or component boundaries
2. they preserve research and rationale from earlier implementation phases

That means some plan files include:

- comparisons with earlier implementations
- references to old repository layouts
- historical notes about work that was not yet implemented at the time that section was written

When a plan file also has an implementation-status section at the top, that status block is the authoritative summary of the file’s current relevance.

## Status vocabulary

The plan files now aim to use this vocabulary consistently:

- **Implemented** — the component exists in code and the plan is now mainly a design/status reference
- **Implemented (initial v1), with deferred follow-ons** — the main baseline exists, but some explicitly deferred expansion remains
- **Partially implemented** — part of the planned surface exists, but significant parts remain open
- **Deferred** — still design-only
- **Historical research note** — primarily preserved for rationale/comparison rather than current implementation guidance

## Current high-level reading order

If you want the shortest path:

1. read `docs/architecture.md`
2. read `plan.md`
3. then use the relevant files under `plans/` for layer- or component-level design detail

Suggested starting points in this directory:

- `plans/knowledgebase.md`
- `plans/informal.md`
- `plans/server.md`
- `plans/toolkit.md`
- `plans/setup.md`

## Important note about historical sections

Historical sections in these files are still useful, but they should not override the current implementation docs.
If a `plans/` file and a `docs/` file disagree about what exists in code today, `docs/` is the source of truth for current implementation behavior.
