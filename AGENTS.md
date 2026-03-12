# AGENTS.md

Minimal guidance for coding agents working in this repository.

## General

- Work from the repository root.
- Prefer small, focused diffs.
- Do not edit `.lake/` contents manually.
- This repository is **PRE-RELEASE** and still **EXPERIMENTAL**.
- Do **not** add compatibility shims, alias modules, deprecated wrappers, or legacy import-path support unless the user explicitly asks for them.
- At this stage, consistency inside this repository matters more than preserving earlier external APIs or import paths.
- Backward compatibility is not required yet; prefer the simplest current design.

## Lean

- Use `lake` for Lean builds/tests.
- Useful commands:
  - `lake build`
  - `lake exe aftk_test`
  - `lake exe aftk_server_test`

## Python

- Use `uv` for all Python interaction.
- Do not invoke bare `python`, `pip`, or `pytest` directly when `uv` should be used instead.
- Typical commands:
  - `uv run python -V`
  - `uv run python -m unittest discover -s tests/python -v`
  - `uv run pyright`
  - `uv run ruff check`

## Validation

- For Lean changes, run the relevant `lake` build/test command.
- For Python client changes, run the Python tests via `uv`.
- For Python code changes, also typecheck and lint:
  - `uv run pyright`
  - `uv run ruff check`
- If you touch both sides, validate both.
