# Plan: pi logging + cost tracking extension

## Goal
Add a second AFTK pi extension that is installed by `lake run aftk_setup` alongside the existing toolkit extension and that:

- stores pi session logs under `.aftk/logs/`
- stores per-run cost summaries under `.aftk/cost/`
- works for both interactive and noninteractive pi CLI runs

## Investigation summary

### What pi already gives us
From pi's `extensions.md` and `session.md`:

- Extensions can subscribe to lifecycle hooks including:
  - `session_directory`
  - `session_start`
  - `agent_end`
  - `message_end`
  - `session_shutdown`
- `session_directory` runs **before** the initial `SessionManager` is created and can override the session directory for CLI runs.
- pi already persists sessions as JSONL files with structured entries.
- assistant session messages already include token and cost data in `message.usage.cost`.
- `agent_end` exposes `event.messages` for the current prompt, which is a good boundary for accumulating **run-local** usage.
- extensions still run in noninteractive modes; only UI methods become unavailable/no-op.

### What the current AFTK integration looks like
From `src/hosts/pi/extension.ts`, `src/hosts/pi/index.ts`, `docs/toolkit/overview.md`, and `docs/aftk_setup.md`:

- the existing AFTK pi entrypoint is intentionally thin
- `registerToolkitExtension(...)` only models the small subset of the pi API needed for tool registration + shutdown cleanup
- `lake run aftk_setup` currently generates:
  - `.pi/extensions/aftk-toolkit.ts`
  - `.pi/APPEND_SYSTEM.md`
- `lakefile.lean` currently hard-codes a single generated extension shim

### Key implementation insight
The cheapest and lowest-risk way to satisfy the logging requirement is:

1. **reuse pi's native session JSONL format** rather than inventing a new log format for normal persisted runs
2. use `session_directory` to redirect session storage into `.aftk/logs/`
3. derive **run summaries** from `agent_end` and flush them into `.aftk/cost/`

This avoids reimplementing pi's session serialization for the common case.

## Recommended design

## 1. Add a separate logging extension entrypoint
Create a new pi extension entrypoint, separate from the toolkit extension.

Proposed file:

- `src/hosts/pi/logging-extension.ts`

Recommendation:

- write this extension against the real pi `ExtensionAPI` typings from `@mariozechner/pi-coding-agent`
- do **not** try to stretch `PiExtensionAPILike` in `src/hosts/pi/index.ts` to cover the full lifecycle API
- keep the existing toolkit extension thin and unchanged in responsibility

Possible helper split if the file gets large:

- `src/hosts/pi/logging/paths.ts`
- `src/hosts/pi/logging/summary.ts`
- `src/hosts/pi/logging/files.ts`

## 2. Redirect session storage into `.aftk/logs/`
Use `pi.on("session_directory", ...)` to return:

- `join(event.cwd, ".aftk", "logs")`

Effect:

- normal interactive runs store their native pi session JSONL files directly in `.aftk/logs/`
- normal noninteractive CLI runs also store their session JSONL files there
- `/continue`, `/resume`, and new sessions stay project-local once the session manager is anchored there

Notes:

- pi documents that explicit `--session-dir` takes precedence over `session_directory`
- pi documents that `session_directory` is CLI-only, which is fine for the `aftk_setup` use case

## 3. Track per-run usage in memory and flush summaries into `.aftk/cost/`
Initialize run state on `session_start`.

Suggested in-memory run state:

- `runId`
- `cwd`
- `startedAt`
- `endedAt`
- `sessionId`
- `sessionFile`
- `persisted`
- `promptCount`
- `assistantMessageCount`
- `toolCallCount`
- `toolResultCount`
- token totals:
  - `input`
  - `output`
  - `cacheRead`
  - `cacheWrite`
  - `total`
- cost totals:
  - `input`
  - `output`
  - `cacheRead`
  - `cacheWrite`
  - `total`
- per-model/provider breakdown keyed by `provider/model`

Update the accumulator on `agent_end` by scanning `event.messages`:

- sum assistant-message `usage`
- count tool calls from assistant content blocks of type `toolCall`
- count `toolResult` messages
- increment prompt/run counters

Why `agent_end` is the right hook:

- it scopes naturally to one user prompt
- it avoids double-counting old history when continuing a session
- it works for interactive and noninteractive runs alike

## 4. Write one cost-summary file per CLI run
Store run summaries in `.aftk/cost/`.

Recommended naming:

- one JSON file per run, keyed by `runId`
- include the linked `sessionFile` path in the JSON

Suggested summary shape:

```json
{
  "schemaVersion": 1,
  "runId": "2026-03-13T21-12-11.123Z_pid12345",
  "cwd": "/path/to/project",
  "startedAt": "...",
  "updatedAt": "...",
  "endedAt": "...",
  "sessionId": "...",
  "sessionFile": ".aftk/logs/...jsonl",
  "persisted": true,
  "runTotals": {
    "prompts": 0,
    "assistantMessages": 0,
    "toolCalls": 0,
    "toolResults": 0,
    "tokens": {
      "input": 0,
      "output": 0,
      "cacheRead": 0,
      "cacheWrite": 0,
      "total": 0
    },
    "cost": {
      "input": 0,
      "output": 0,
      "cacheRead": 0,
      "cacheWrite": 0,
      "total": 0
    }
  },
  "byModel": {
    "anthropic/claude-sonnet-4-5": {
      "assistantMessages": 0,
      "toolCalls": 0,
      "tokens": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "total": 0 },
      "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "total": 0 }
    }
  }
}
```

Implementation details:

- write/update the summary after every `agent_end`
- do a final flush on `session_shutdown`
- use atomic writes (`tmp` + rename) so summaries are never half-written

## 5. Decide how to handle non-persisted sessions
There is one edge case that needs an explicit decision:

- `--no-session` creates an in-memory session manager

Recommended implementation order:

### Phase 1
Support the normal persisted case first:

- redirect native session files into `.aftk/logs/`
- always emit `.aftk/cost/<runId>.json`

### Phase 2
Close the in-memory gap if needed:

- if `ctx.sessionManager.isPersisted() === false`, create a synthetic JSONL mirror under `.aftk/logs/`
- append entries on `message_end`
- use a simple linear parent chain for the synthetic log

If we want the first implementation smaller, we can ship Phase 1 first and document that `--no-session` is an opt-out from persistent logs.

## 6. Install it with `lake run aftk_setup`
Update `lakefile.lean` so `aftk_setup` writes a second managed shim.

Current generated files:

- `.pi/extensions/aftk-toolkit.ts`
- `.pi/APPEND_SYSTEM.md`

Proposed generated files:

- `.pi/extensions/aftk-toolkit.ts`
- `.pi/extensions/aftk-logging.ts`
- `.pi/APPEND_SYSTEM.md`

Recommended refactor:

- replace the single-shim logic with a small list of generated extension shims
- keep the same generated-file marker and overwrite policy
- print both shim installation/update statuses in the success summary

## 7. Keep package metadata aligned
Update `package.json` so pi package discovery stays aligned with `aftk_setup`.

Recommended changes:

- add the logging extension entrypoint to `pi.extensions`
- optionally add an explicit export such as `./pi-logging-extension` for symmetry/documentation

This is not strictly required for the local `aftk_setup` shims, but it keeps package-mode behavior consistent.

## 8. Documentation updates
Update the docs that currently assume a single pi extension shim.

Files likely needing edits:

- `README.md`
- `docs/aftk_setup.md`
- `docs/toolkit/overview.md`
- `docs/toolkit/library.md`
- possibly `docs/architecture.md`

Topics to update:

- `aftk_setup` now installs two extensions
- what lives in `.aftk/logs/`
- what lives in `.aftk/cost/`
- any limitations around `--session-dir` / `--no-session`

## 9. Repo hygiene
If the generated logs/cost summaries are meant to stay local, add ignores for them.

Likely `.gitignore` additions:

- `/.aftk/logs`
- `/.aftk/cost`

## 10. Tests
Add focused TypeScript-side coverage.

Recommended test areas:

### Unit tests
Add a new host/pi test file for logging behavior, e.g.

- `tests/toolkit/hosts/pi-logging.unit.test.ts`

Cover at least:

- `session_directory` returns `<cwd>/.aftk/logs`
- `agent_end` usage aggregation is correct
- per-model aggregation is correct
- `session_shutdown` final flush happens
- cost summary naming/path logic

### Existing pi-adapter tests
Keep `tests/toolkit/hosts/pi.unit.test.ts` for the toolkit extension itself.
Do not overload it with logging-specific behavior.

### Setup-script coverage
At minimum, manually verify during implementation that:

- `lake run aftk_setup` creates both shims
- rerunning the script is idempotent
- user-managed files are still protected

## Suggested implementation order

1. add `src/hosts/pi/logging-extension.ts`
2. implement run-state accumulation + summary-file writing
3. wire `session_directory` to `.aftk/logs/`
4. update `package.json` pi metadata
5. refactor `lakefile.lean` to generate `aftk-logging.ts` as a second shim
6. update docs
7. add tests
8. optionally add Phase 2 synthetic logging for in-memory sessions

## Deliverable definition
The feature is done when all of the following are true:

- `lake run aftk_setup` installs both the toolkit shim and the logging shim
- a normal interactive pi run writes/uses a session JSONL file in `.aftk/logs/`
- a normal noninteractive pi run writes/uses a session JSONL file in `.aftk/logs/`
- each CLI run produces a JSON cost summary in `.aftk/cost/`
- continuing an old session does not double-count historical cost in the new run summary
- docs explain the behavior and any intentional limitations
