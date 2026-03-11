# AGENTS.md

Minimal guidance for coding agents working in this repository.

## General

- Work from the repository root.
- Prefer small, focused diffs.
- Do not edit `.lake/` contents manually.

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

## Validation

- For Lean changes, run the relevant `lake` build/test command.
- For Python client changes, run the Python tests via `uv`.
- If you touch both sides, validate both.
