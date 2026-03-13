# Plan: add an `aftk_chat` entrypoint backed by Pydantic AI's clai interface

## Goal

Add a second user-facing entrypoint that launches the **interactive Pydantic AI chat UI** for the
same agent configuration currently used by `main.py`.

Desired UX:

- in this repo: `uv run aftk_chat`
- in a downstream Lake workspace: `lake run aftk_chat`

The chat session should use the **same agent setup** as the existing one-shot runner in `main.py`:

- same model selection
- same reasoning/model settings
- same system instructions
- same coding toolkit
- same AFTK toolkit/project-root resolution

---

## What I inspected

### Repository code

I read:

- `main.py`
- `pyproject.toml`
- `lakefile.lean`
- `plans/simple_agent.md`

Relevant current structure:

- `build_agent(...)` already constructs the shared agent
- `build_model_settings(...)` already constructs the per-run reasoning settings
- `load_app_config(...)` / Hydra config already drive the one-shot CLI
- `lakefile.lean` already has a downstream-friendly launcher for `aftk` that forwards
  `--config-path <workspace-root>` by default

### Pydantic AI docs

From `https://ai.pydantic.dev/llms.txt`, I followed the CLI documentation:

- CLI / clai docs: https://ai.pydantic.dev/cli/index.md

Key documented APIs/features from that page:

1. **clai supports custom agents** via `--agent module:variable`
2. **Agents can launch the chat UI directly** with:
   - `Agent.to_cli_sync()`
   - `await Agent.to_cli()`
3. `Agent.to_cli_sync()` / `Agent.to_cli()` support:
   - `prog_name`
   - `message_history`
4. The interface is an **interactive chat session** when no one-shot prompt is supplied
5. There is also a separate **web UI** (`clai web`), but that is distinct from the terminal chat UI

I also inspected the installed `pydantic_ai` package to confirm the current runtime API surface.
In this environment:

- `Agent.to_cli(...)` exists
- `Agent.to_cli_sync(...)` exists
- both accept `prog_name`, `message_history`, and `model_settings`

---

## Findings

### 1. `Agent.to_cli_sync()` is the best fit for `aftk_chat`

The docs explicitly support launching the terminal chat interface directly from an `Agent` instance:

```python
agent.to_cli_sync()
```

That is a much better fit than shelling out to the standalone `clai` executable because we already
have code that builds the exact agent we want.

Using `to_cli_sync()` lets us:

- reuse `build_agent(...)`
- reuse `build_model_settings(...)`
- keep all toolkit wiring in one place
- avoid duplicating agent definition in a separate importable module-level variable

### 2. We should reuse the existing agent-building path, not define a second agent

The user explicitly wants the chat interface to talk to the **same agent** used by `main.py`.

Right now, the important shared logic already lives in `main.py`:

- config loading
- toolkit cwd resolution
- AFTK project-root detection
- model route construction
- reasoning settings

So the implementation should not build a separate chat-only agent definition.
Instead, it should add a small chat entrypoint that calls into the existing helpers.

### 3. `prompts.user_prompt` should not be auto-sent in chat mode

In the one-shot runner, `prompts.user_prompt` is the actual prompt sent to the agent.

For an interactive chat UI, that behavior would be surprising: the user expects to type the first
message themselves.

So for `aftk_chat`:

- reuse `prompts.system_prompt`
- reuse model + tools + reasoning settings
- **do not** automatically send `prompts.user_prompt`

If we later want a chat-specific opening prompt/history, that can be added explicitly, but it should
not be part of the first pass.

### 4. `prog_name` should be set to `aftk_chat`

The docs show that `Agent.to_cli_sync()` supports `prog_name`, and the installed implementation uses
that name in the interactive prompt and CLI labeling.

So we should launch chat with:

```python
agent.to_cli_sync(prog_name="aftk_chat", ...)
```

That gives a clean prompt like:

```text
aftk_chat ➤
```

### 5. We should pass the configured model settings into the chat session

The installed `Agent.to_cli_sync()` / `Agent.to_cli()` APIs accept `model_settings`.

That means the same reasoning configuration currently used by the one-shot runner can also be used
for interactive chat:

```python
build_model_settings(
    resolved_config.agent.reasoning,
    resolved_config.agent.reasoning_summary,
)
```

This is important for keeping the chat agent behavior aligned with the one-shot agent.

### 6. We still need a dedicated launcher in both Python packaging and Lake

To make the UX match the existing `aftk` command, we need two entrypoints:

1. a Python console script:
   - `aftk_chat`
2. a Lake script for downstream workspaces:
   - `lake run aftk_chat`

The Lake launcher should mirror the existing `aftk` behavior and forward:

- `--config-path <workspace-root>`

by default, unless the user already supplied `--config-path`.

---

## Recommended implementation shape

### 1. Add a shared helper for “agent from config” construction

The current one-shot path builds the agent inline inside `run_agent_from_config(...)`.
To avoid duplicating that setup for chat mode, extract a helper such as:

```python
def build_agent_from_config(
    config: AppConfig | DictConfig | Mapping[str, Any],
    *,
    base_dir: str | Path | None = None,
    model: Model | str | None = None,
    toolsets: Sequence[AbstractToolset[None]] | None = None,
) -> tuple[AppConfig, Agent[None, str], OpenAIResponsesModelSettings, Path]:
    ...
```

Suggested return values:

- resolved `AppConfig`
- constructed `Agent`
- constructed model settings
- resolved toolkit cwd

That helper can then be reused by:

- `run_agent_from_config(...)`
- the new chat entrypoint

This is the most direct way to guarantee the chat mode and one-shot mode stay in sync.

### 2. Add a chat launcher function in `main.py`

Add a function along the lines of:

```python
def chat_from_config(
    config: AppConfig | DictConfig | Mapping[str, Any],
    *,
    base_dir: str | Path | None = None,
    model: Model | str | None = None,
    toolsets: Sequence[AbstractToolset[None]] | None = None,
) -> None:
    ...
```

Behavior:

- load config
- build the same agent as the one-shot runner
- compute model settings from config
- call:

```python
agent.to_cli_sync(
    prog_name="aftk_chat",
    model_settings=model_settings,
)
```

This function should **not** save trace/output artifacts.
The chat UI is interactive and multi-turn, so the one-shot trace/output behavior does not map
cleanly onto it.

### 3. Add a Hydra entrypoint for chat mode

Keep the current `@hydra.main(...)` pattern and add a second Hydra-backed entrypoint in `main.py`,
for example:

```python
@hydra.main(...)
def _hydra_chat_cli(cfg: DictConfig) -> None:
    ...
```

That entrypoint should:

- use `load_app_config(cfg)`
- compute `original_cwd = Path(get_original_cwd())`
- call `chat_from_config(..., base_dir=original_cwd)`

Then expose a public console entrypoint:

```python
def chat_cli() -> None:
    _hydra_chat_cli()
```

### 4. Add a Python script entrypoint in `pyproject.toml`

Extend:

```toml
[project.scripts]
aftk = "main:cli"
```

to also include:

```toml
aftk_chat = "main:chat_cli"
```

That gives:

```text
uv run aftk_chat
```

inside this repo.

### 5. Add a Lake script `aftk_chat`

In `lakefile.lean`, add a second script modeled on `script aftk`.

Recommended approach:

- factor the existing launcher logic into a shared helper, e.g. a private function that:
  - finds the `aftk` package directory
  - injects downstream `--config-path` by default
  - spawns `uv run --project <aftk-package> <script-name> ...`
- use it for both:
  - `script aftk`
  - `script aftk_chat`

That keeps downstream behavior consistent and avoids duplicating the config-path-forwarding logic.

### 6. Update README usage docs

Add a short section documenting:

- `uv run aftk_chat`
- `lake run aftk_chat`
- that downstream Lake launchers resolve `config.yaml` from the caller workspace by default

---

## Why not use `clai --agent module:variable` directly?

The docs do support that pattern, but it is not the best fit here.

Problems with that approach in this repository:

1. our agent is not just a static module-level constant; it depends on:
   - Hydra-loaded config
   - the caller workspace / `base_dir`
   - resolved coding toolkit cwd
   - AFTK project-root detection
2. a module-level exported `agent = ...` would not naturally pick up downstream workspace context
3. we already have a clean programmatic API via `Agent.to_cli_sync()`

So the direct-agent-launch API is the simpler and safer path.

---

## Test plan

### Python tests

Add focused tests in `tests/python/test_simple_agent.py` or a nearby file.

Recommended cases:

1. **Shared agent construction is reused**
   - verify the helper used by chat mode exposes the same coding + AFTK tools as the one-shot path

2. **Chat launcher uses configured model settings**
   - patch/mock `Agent.to_cli_sync`
   - assert it is called with:
     - `prog_name="aftk_chat"`
     - `model_settings=build_model_settings(...)`

3. **Chat launcher resolves base_dir correctly**
   - build from a temp cwd or repo root
   - assert the resulting tool configuration is anchored the same way as the one-shot runner

4. **Hydra config path behavior remains intact**
   - ensure the chat entrypoint uses the same config-loading behavior as `aftk`

### Manual validation

In this repo:

- `uv run aftk_chat`

In a downstream repo:

- `lake run aftk_chat`

Expected behavior:

- chat prompt opens interactively
- prompt label is `aftk_chat`
- agent has both coding tools and AFTK tools when available
- downstream launcher uses downstream `config.yaml` by default

---

## Non-goals for the first pass

Do **not** add these yet unless explicitly requested:

- `clai web` / browser UI support
- extra chat-specific config fields
- persisted multi-session transcript storage owned by this repo
- replaying `prompts.user_prompt` automatically on chat startup
- reimplementing the full standalone `clai` argument surface (`--no-stream`, one-shot prompt mode, etc.)

The first pass should only provide a straightforward interactive terminal chat entrypoint for the
existing configured agent.

---

## Summary

The smallest clean implementation is:

- keep `main.py` as the single source of truth for agent construction
- extract a shared “build agent from config” helper
- add `chat_from_config(...)`
- add a Hydra-backed `chat_cli()` entrypoint in `main.py`
- add:
  - `aftk_chat = "main:chat_cli"` in `pyproject.toml`
  - `script aftk_chat` in `lakefile.lean`

And launch the interactive session with:

```python
agent.to_cli_sync(
    prog_name="aftk_chat",
    model_settings=build_model_settings(...),
)
```

That gives the requested `aftk_chat` UX while keeping the chat agent identical to the one-shot
agent in all the ways that matter.