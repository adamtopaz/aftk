# `aftk_autoformalize_loop` Lake script

`aftk_autoformalize_loop` is a Lake script defined in `lakefile.lean`.
It runs `pi` in noninteractive print mode in a fresh stigmergic loop until the agent is confident that the whole task is done.

Run it with a direct task prompt:

```text
lake run aftk_autoformalize_loop Formalize the next leaf from entrypoint.md
```

Or read the task text from a file:

```text
lake run aftk_autoformalize_loop --task-file path/to/task.md
```

Show help with:

```text
lake run aftk_autoformalize_loop --help
```

## Core behavior

Each iteration:

- runs `pi --print --no-session`
- starts fresh and does **not** use `--continue`
- expects the agent to work stigmergically from durable repo state
- continues when pi exits with an error
- continues when the assistant ends with `AFTK_LOOP_CONTINUE`
- continues when the assistant forgets the marker
- stops only when the assistant's final nonempty line is exactly `AFTK_LOOP_DONE`

This means the script treats repo state as the coordination channel.
The agent is expected to inspect the current repository each time rather than relying on hidden chat memory.

## Prompt behavior

The loop prompt is built from:

- `src/hosts/pi/AUTOFORMALIZE_LOOP_PROMPT.template.md`

The script appends:

- the user-supplied task
- the current iteration number
- the stop/continue marker contract

The template tells the agent to:

- read `entrypoint.md` first when present
- prefer `informal_*`, `knowledgebase_*`, and targeted `aftk_*` queries before generic repo search
- inspect repo state before editing
- treat the informal and knowledge-base layers as editable coordination artifacts, not just read-only lookup targets
- use built-in file tools for ordinary file work, precise edits, and direct updates to informal / knowledge-base artifacts not covered by mutation tools
- use `informal_*` and `knowledgebase_*` to find the frontier first
- use `aftk_*` Lean tools only after locating the exact proof site
- make one meaningful chunk of progress unless whole-task completion is genuinely feasible in one run

## Downstream-project behavior

The script is designed to work in downstream Lake workspaces that depend on `aftk`.
It resolves the `aftk` package through Lake and then ensures pi gets the needed AFTK resources.

If the downstream workspace already has the standard local AFTK pi setup files:

- `.pi/extensions/aftk-toolkit.ts`
- `.pi/extensions/aftk-logging.ts`
- `.pi/APPEND_SYSTEM.md`

then the script relies on normal pi auto-discovery.

If any of those files are missing, the script loads the missing pieces directly from the resolved `aftk` package:

- toolkit extension entrypoint: `src/hosts/pi/extension.ts`
- logging extension entrypoint: `src/hosts/pi/logging-extension.ts`
- appended system guidance: `src/hosts/pi/APPEND_SYSTEM.template.md`

So the script can be used even when `lake run aftk_setup` has not been run yet.

## Logging and cost tracking

The loop uses `--no-session` on purpose so each pi run is fresh.
The AFTK logging extension still persists local artifacts by mirroring the ephemeral session:

- logs under `.aftk/logs/`
- per-run cost summaries under `.aftk/cost/`

## Options

Supported script options:

- `--task-file <path>`
- `--max-steps <n>`
- `--provider <name>`
- `--model <pattern>`
- `--thinking <level>`

`--max-steps` is only a safety override.
If omitted, the loop is intentionally unbounded and stops only on `AFTK_LOOP_DONE`.

## Related docs

- `docs/aftk_setup.md`
- `docs/toolkit/overview.md`
- `docs/toolkit/library.md`
