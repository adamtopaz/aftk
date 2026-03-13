# Plan: split `aftk_chat` into a separate manual-Hydra entrypoint

## Goal

Keep `uv run aftk` as the normal Hydra-backed one-shot CLI in `main.py`, and move the interactive
`aftk_chat` path into its own Python file.

The new chat file should:

- contain the chat-specific entrypoint code
- avoid `@hydra.main`
- load/compose the Hydra config manually
- keep reusing the existing shared agent-building helpers
- stop forcing the repo-wide Hydra logging setup to accommodate the chat TUI

That should let us simplify the current logging setup and return `aftk` to the standard Hydra
logging behavior.

---

## What I inspected

I read the current implementations and references in:

- `main.py`
- `config.yaml`
- `pyproject.toml`
- `lakefile.lean`
- `tests/python/test_simple_agent.py`
- `README.md`
- `plans/clai.md`

---

## Current state

### Python

`main.py` currently mixes three concerns:

1. shared app/config/agent helpers
2. the one-shot Hydra CLI for `uv run aftk`
3. the interactive chat CLI for `uv run aftk_chat`

Relevant pieces:

- `build_agent_from_config(...)` already gives us a good shared seam
- `chat_from_config(...)` already exists, but lives in `main.py`
- `_hydra_chat_cli(...)` uses `@hydra.main(...)`
- `chat_cli()` is the console-script entrypoint and just delegates to `_hydra_chat_cli()`

### Hydra/logging

The repo currently has chat-driven Hydra/logging accommodations in two places:

- `config.yaml`
  - custom `hydra.job_logging.handlers.console.stream=ext://sys.stderr`
  - custom `hydra.hydra_logging.handlers.console.stream=ext://sys.stderr`
  - extra logger-level overrides under `hydra.job_logging.loggers`
- `lakefile.lean`
  - default forwarding of the same Hydra logging overrides for both `aftk` and `aftk_chat`

### Tests/docs

- `tests/python/test_simple_agent.py` asserts those Hydra logging defaults
- `pyproject.toml` points `aftk_chat` at `main:chat_cli`
- `README.md` documents `uv run aftk_chat` / `lake run aftk_chat`

---

## Refactor direction

## 1. Move chat-only code into a dedicated Python module

Recommended shape for a small diff:

- keep the shared helper layer in `main.py` for now
- create a new top-level module such as `chat_cli.py`
- move the chat-specific functions there:
  - `chat_from_config(...)`
  - a new manual config-loading helper
  - the `cli()` entrypoint for `aftk_chat`

Why this shape:

- it cleanly separates `aftk_chat` from the `aftk` CLI file
- it avoids a larger package/module reorganization right now
- it still reuses `build_agent_from_config(...)` from `main.py`

Non-goal for this refactor:

- do **not** simultaneously move all shared app helpers out of `main.py` unless the implementation
  becomes awkward enough to require it

---

## 2. Replace `@hydra.main` in chat mode with manual config composition

The new chat module should not use `@hydra.main`.

Instead, it should manually:

1. parse a small chat CLI surface
2. choose the config directory/name
3. call Hydra's compose API
4. pass the resolved config into `chat_from_config(...)`

Recommended supported arguments for `aftk_chat`:

- `--config-path` / `-cp`
- `--config-name` / `-cn` (default: `config`)
- remaining positional tokens treated as Hydra override strings, e.g.
  - `agent.model=gpt-5.4-pro`
  - `toolkit.cwd=.`
  - `++foo.bar=baz`

Recommended implementation sketch:

```python
with hydra.initialize_config_dir(config_dir=str(config_dir), version_base="1.3", job_name="aftk_chat"):
    cfg = hydra.compose(config_name=config_name, overrides=overrides)
```

Important behavior choices:

- keep the **config default** aligned with the current behavior
  - default config dir should still be the repo/root config location unless overridden
- use `Path.cwd()` as the chat `base_dir`
  - this replaces the previous `get_original_cwd()` dependency
  - with `lake run aftk_chat`, the process cwd is already the downstream workspace root
- do **not** try to fully emulate the entire Hydra CLI surface for chat
  - no need to support every Hydra flag like `--cfg`, `--multirun`, etc.
  - if unsupported Hydra-only flags show up, fail clearly instead of silently mis-parsing them

Rationale:

`aftk_chat` is mostly a testing/debugging UI, so a lightweight loader is enough. `uv run aftk`
remains the full Hydra-native CLI.

---

## 3. Remove chat code from `main.py`

After adding the dedicated chat module:

- remove `chat_from_config(...)` from `main.py`
- remove `_hydra_chat_cli(...)`
- remove `chat_cli()` from `main.py`
- keep `cli()` / `_hydra_cli(...)` in `main.py` as the one-shot Hydra path

At that point, `main.py` is back to being the `aftk` CLI plus shared helpers, not the chat entrypoint.

---

## 4. Revert the Hydra logging hacks

Once chat is no longer running under `@hydra.main`, we should simplify the logging setup back toward
normal Hydra usage.

Planned changes:

### `config.yaml`

Remove the custom chat-driven logging block:

- `hydra.job_logging.handlers.console.stream`
- `hydra.hydra_logging.handlers.console.stream`
- the extra `hydra.job_logging.loggers.*` overrides unless we discover they are still needed for a
  separate reason

Keep the non-logging Hydra settings that still matter:

- `hydra.run.dir`
- `hydra.sweep.dir`
- `hydra.sweep.subdir`
- `hydra.job.chdir: false`

### `lakefile.lean`

Simplify the launcher helpers:

- remove:
  - `hasHydraJobLoggingOverride`
  - `hasHydraHydraLoggingOverride`
  - `defaultHydraLoggingArgs`
- stop injecting default Hydra logging overrides for both launchers
- continue forwarding a default `--config-path <workspace-root>` when the caller did not supply one

This is the key cleanup enabled by the refactor.

---

## 5. Update packaging/entrypoints

### `pyproject.toml`

Change the chat console script to point at the new module, for example:

```toml
[project.scripts]
aftk = "main:cli"
aftk_chat = "chat_cli:cli"
```

Because this repo currently uses top-level Python modules, also update:

```toml
[tool.setuptools]
py-modules = ["main", "chat_cli"]
```

If implementation ends up preferring a package module instead, e.g. `aftk.chat_cli`, that is also
fine, but the minimal-diff path is a second top-level module.

### `lakefile.lean`

Keep `script aftk_chat`, but make sure it only forwards the config-path default and not the old
logging overrides.

---

## 6. Tests to update

### Python tests

Adjust `tests/python/test_simple_agent.py` to reflect the new split:

- import `chat_from_config` from the new chat module
- keep the existing `prog_name="aftk_chat"` assertion
- add targeted tests for the manual chat config loader, e.g.
  - `--config-path` selects the right config directory
  - override strings are passed through to Hydra compose
  - unsupported Hydra-only flags fail with a clear error

Remove or replace the old logging-default test:

- `test_hydra_logging_defaults_write_console_logs_to_stderr`

That test should disappear because the custom stderr-forcing behavior is the thing we are removing.

### Lean/build validation

Because `lakefile.lean` changes, include a Lean-side validation pass as part of the refactor.

---

## 7. Docs to update

### `README.md`

Update the Python CLI section to reflect the new split:

- `aftk` remains the Hydra-backed one-shot CLI
- `aftk_chat` is a lightweight interactive chat/testing entrypoint that manually composes the config
- document the chat config knobs we still support directly:
  - `--config-path`
  - optional overrides

We should keep the downstream story unchanged:

- `uv run aftk_chat`
- `lake run aftk_chat`

with `lake run aftk_chat` still defaulting to the downstream workspace root for config resolution.

---

## Recommended implementation order

1. Add `chat_cli.py` with manual Hydra compose + `chat_from_config(...)`
2. Point `aftk_chat` in `pyproject.toml` to the new module
3. Delete chat-specific Hydra entrypoints from `main.py`
4. Remove the custom Hydra logging config from `config.yaml`
5. Simplify `lakefile.lean` to stop injecting logging overrides
6. Update Python tests
7. Update `README.md`
8. Run validation

This order keeps the shared agent behavior stable while peeling away the chat-specific Hydra setup.

---

## Validation plan

Because this touches both Python and the Lake launcher, validate both sides:

### Python

- `uv run python -m unittest discover -s tests/python -v`
- `uv run pyright`
- `uv run ruff check`

### Lean / launcher

- `lake build`

### Smoke checks

- `uv run aftk --cfg job`
- `uv run aftk_chat --config-path .`
- `lake run aftk_chat`

For the smoke checks, confirm:

- `aftk` still loads config through Hydra normally
- `aftk_chat` launches the interactive UI
- the prompt label is still `aftk_chat`
- downstream config-path forwarding still works

---

## Scope decisions / open questions

### 1. Should `aftk_chat` support the full Hydra CLI surface?

Recommendation: **no**.

Support only the small subset needed for chat/testing:

- config path/name
- ordinary Hydra override strings

Anything beyond that is better left to `uv run aftk`.

### 2. Should we move shared helper code out of `main.py` now?

Recommendation: **not necessarily**.

For this refactor, reusing the existing shared helpers from `main.py` is the smallest focused diff.
If that import layering becomes annoying, we can do a second cleanup later.

### 3. Should we keep the custom third-party logger level overrides?

Recommendation: default to **removing them together with the stderr stream hacks**, unless we find a
clear one-shot-CLI reason to keep them.

The user's requested simplification points toward returning to the standard Hydra setup.
