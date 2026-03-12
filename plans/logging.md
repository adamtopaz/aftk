# Plan: improved CLI and runtime logging for AFTK

## Goal

Improve AFTK's operator-facing logging so a user running:

- `uv run autoformalize ...`
- `lake run autoformalize ...`

can see what the framework is doing in real time, at multiple verbosity levels, without having to wait for post-hoc `.aftk/runs/run-*/` artifacts.

The desired outcome is:

- useful live progress in the terminal
- true live traces of agent execution, not just post-hoc summaries after a run step finishes
- a persistent CLI/session log with framework events, not just provider HTTP traffic
- clear per-run diagnostics for runner phases, task transitions, tool calls, retries, command execution, and failures
- configurable verbosity so normal runs are readable and debug runs are exhaustive

## Non-goals

- replacing the existing `.aftk/runs/run-*/{run.json,messages.json,llm-calls.jsonl,tool-calls.jsonl,...}` telemetry artifacts
- removing all dependency logs entirely
- designing a remote observability stack or external log ingestion system
- logging raw secrets, API keys, or unbounded prompt/tool payloads by default

The existing persisted run artifacts are still valuable; this work should make the live CLI experience and top-level log file much better.

## Research summary

### 1. Current behavior is mostly "whatever external libraries emit"

`aftk/cli.py` currently:

- builds the Hydra config
- constructs `FrameworkRunner`
- runs it with `asyncio.run(...)`
- prints the final `RunnerLoopResult`

It does **not** currently initialize an AFTK logging policy.
There is no repo-local `logging.basicConfig(...)`, no framework logger hierarchy, and no CLI logging config surface.

A repo search for logging setup found essentially no framework-owned Python logging configuration.

### 2. The current `cli.log` is dominated by `httpx` INFO lines

The live file `../capacity/cli.log` shows repeated lines like:

- `HTTP Request: POST https://api.openai.com/v1/chat/completions "HTTP/1.1 200 OK"`

This confirms the user's complaint:

- the log contains network/provider activity
- but not the higher-value framework lifecycle events
- so it is hard to answer "what is the runner doing right now?"

### 3. AFTK already persists rich post-hoc artifacts, but not operator-friendly live logs

The runner and storage layers already persist a lot of useful data:

- `run.json`
- `result.json`
- `messages.json`
- `llm-calls.jsonl`
- `tool-calls.jsonl`
- `coding-actions.jsonl`
- `usage.json`
- `cost.json`
- `project-rollups.json`

Relevant code paths:

- `aftk/runner.py`
- `aftk/storage/runs.py`
- `aftk/storage/telemetry.py`
- `aftk/coding/logs.py`

This means the framework already has a strong event model and telemetry vocabulary.
The main gap is that it is written mostly as end-of-step artifacts rather than streamed into a coherent operator log while the run is in progress.

### 4. The runner already has natural lifecycle boundaries we can log

From `aftk/runner.py`, the framework has clear points where logging would be useful:

- runner start / end
- initializer start / end
- orchestrator start / end
- worker start / end
- task claiming / attempt creation / attempt completion
- decision validation / patch application / task creation
- run finalization / rollup rebuild
- exception path handling

These are ideal logging boundaries because they are high signal and already explicit in the control flow.

### 5. Coding/tool execution already has useful data we can surface live

`coding-actions.jsonl` records:

- file reads/writes/edits
- command execution
- durations / exit codes / paths

`tool-calls.jsonl` and `llm-calls.jsonl` record:

- tool names
- input/output summaries
- statuses
- durations
- retry prompts / failures

So we do **not** need to invent a new concept of events from scratch.
We should reuse these concepts in the live logger.

### 6. Pydantic AI supports streaming agent events, and this should be the primary path for live traces

Pydantic AI's docs (`agent.run(..., event_stream_handler=...)`, `run_stream_events()`, `iter()`) support streaming model/tool events during a run.

This is the right mechanism for the user's stated requirement: seeing exactly what is going on while the run is still in progress.

It gives us a direct way to surface live trace events for:

- model request/response boundaries
- streamed text / thinking / tool-call arg deltas
- tool call scheduling and execution
- tool results and retry prompts
- final result emission

So live tracing should not be treated as a later nice-to-have. It should be a first-class requirement, with framework lifecycle logs layered on top of those streaming agent events.

## Operator requirements

The logging system should let an operator answer these questions quickly:

1. Is the run still alive?
2. Which role is currently running?
3. Which task / attempt is being worked on?
4. Which tool is being called right now?
5. What arguments is the model currently constructing for that tool?
6. Which command is currently running, and did it fail?
7. If a tool fails, was it retried or did it abort the run?
8. What run id should I inspect under `.aftk/runs/`?
9. What was the last meaningful event before the run stalled or failed?

## Design principles

### 1. Prefer framework events over transport noise

The default log should emphasize:

- runner lifecycle
- task lifecycle
- tool calls
- command execution
- retries / warnings
- final outcomes

not raw HTTP request lines.

Dependency/network logs should be subordinate and configurable.

### 2. Separate human-friendly progress logs from live traces and structured machine logs

We want three complementary outputs:

- **console progress log** for humans
- **live trace stream** for fine-grained in-progress agent activity
- **structured JSONL event log** for exact inspection / tooling

The console should be concise.
The live trace stream should expose the step-by-step agent activity while it happens.
The structured log should preserve identifiers and fields for debugging.

### 3. Support multiple verbosity levels cleanly

A single log stream should not have to satisfy all audiences at once.

At minimum, support:

- `warning` — only problems and important recoveries
- `info` — normal operational progress
- `debug` — detailed framework/tool activity

Optionally later:

- a `trace`-like mode, or separate payload toggles, for near-complete request/tool detail

### 4. Do not dump raw payloads by default

Even if we can log prompts, tool args, command outputs, and provider payloads, default logs should use summaries and truncation.

Large/raw payload logging should be opt-in.

### 5. Align live logs with persisted run artifacts

Every important log line should include enough context to jump to persisted artifacts:

- `run_id`
- `agent_role`
- `task_id`
- `attempt_id`

That keeps live logs and `.aftk/runs/` aligned.

## Proposed logging model

## 1. Make live traces a first-class CLI feature

The CLI should support an explicit live tracing mode, for example:

```yaml
logging:
  level: info
  live_traces: true
  trace_model_events: summary   # off | summary | full
  trace_tool_events: true
  trace_thinking_deltas: false
```

When enabled, AFTK should stream agent events during execution using Pydantic AI's event streaming hooks, not merely write summaries after each run step finishes.

Representative live trace lines might look like:

- `TRACE run_id=run-0010 role=worker model_response tool_call=lake_build`
- `TRACE run_id=run-0010 role=worker tool_start name=lake_build args={timeout_seconds:120000}`
- `TRACE run_id=run-0010 role=worker tool_end name=lake_build exit_code=1 duration_s=1.55`
- `TRACE run_id=run-0005 role=initializer retry tool=load_node reason='Call open(path=...) first'`

## 2. Add a first-class logging config section to the CLI

Extend the Hydra CLI config with a new logging section, for example:

```yaml
logging:
  level: info
  console: true
  file: true
  file_path: .aftk/cli.log
  file_format: text   # later: text | json
  dependency_level: warning
  include_http: false
  include_llm_payloads: false
  include_tool_payloads: summary   # none | summary | full
  include_command_output: summary  # none | summary | full
```

This should be available via Hydra overrides, e.g.:

- `logging.level=debug`
- `logging.include_http=true`
- `logging.include_tool_payloads=full`

## 3. Centralize setup in a dedicated module

Create a dedicated module such as:

- `aftk/logging.py`

Responsibilities:

- configure Python logging once at CLI startup
- install console/file handlers
- choose formatter(s)
- normalize log levels
- tune noisy dependency loggers
- provide helper adapters or context filters for `run_id`, `task_id`, etc.

This avoids ad hoc logging scattered through the codebase.

## 4. Define a logger namespace hierarchy

Use stable logger names such as:

- `aftk.cli`
- `aftk.runner`
- `aftk.tasks`
- `aftk.agents.initializer`
- `aftk.agents.orchestrator`
- `aftk.agents.worker`
- `aftk.tools`
- `aftk.toolkit`
- `aftk.coding`
- `aftk.storage`

This makes selective verbosity and filtering practical.

## 5. Add high-signal INFO logs at framework boundaries

At `info` level, log only the major steps, for example:

- CLI config summary at startup
- resolved project root / state dir
- runner started / finished
- initializer/orchestrator/worker run start/end
- chosen run id and artifact directory
- task claim / task completion / task blocked / project done
- command start/end for important commands like `lake build`
- warnings for retries, non-zero command exits, and unexpected conditions

Representative examples:

- `INFO aftk.runner start project=/home/dev/capacity state_dir=.aftk max_iterations=40`
- `INFO aftk.runner run_start run_id=run-0010 role=worker task_id=task-0001 attempt_id=attempt-0002 model=openai:gpt-5-mini`
- `INFO aftk.coding command_start run_id=run-0010 argv=['lake','build'] cwd=. timeout=120`
- `WARNING aftk.coding command_exit run_id=run-0010 argv=['lake','build'] exit_code=1`
- `INFO aftk.runner run_end run_id=run-0010 role=worker status=completed duration_s=79.2`

## 6. Add DEBUG logs for exact step tracing

At `debug` level, log the detailed internal events operators need for diagnosis:

- orchestrator selected task and rationale summary
- task patch application summary
- worker brief summary
- tool call start/end with summarized args/results
- retry prompt creation and retry counts
- command stdout/stderr previews
- rollup rebuild summaries
- toolkit client method calls and JSON-RPC errors

Representative examples:

- `DEBUG aftk.runner decision run_id=run-0009 selected_task_id=task-0001 new_tasks=0 patches=2`
- `DEBUG aftk.tools tool_start run_id=run-0008 tool=open args={'path':'Capacity.lean'}`
- `DEBUG aftk.tools tool_retry run_id=run-0005 tool=load_node reason='Call open(path=...) first'`
- `DEBUG aftk.coding command_output run_id=run-0010 stdout_preview='✖ [2/3] Building Capacity ...'`

## 7. Treat dependency logs separately

By default, set noisy dependency loggers to `WARNING`, including likely:

- `httpx`
- `httpcore`
- `openai`
- possibly `asyncio`

Then make them opt-in via config, e.g.:

- `logging.include_http=true`
- or `logging.dependency_level=info`

This preserves access to transport logs without letting them drown out framework events.

## 8. Add a structured event log alongside the text log

In addition to human-readable `cli.log`, add a structured event stream, for example:

- project-wide: `.aftk/events.jsonl`
- or per-run: `.aftk/runs/run-XXXX/events.jsonl`

Each event should include fields like:

- timestamp
- level
- logger
- event_type
- message
- run_id
- agent_role
- task_id
- attempt_id
- model_name
- tool_name
- command argv / exit code / duration when relevant

This gives us exact, machine-readable run timelines without parsing text logs.

## 9. Keep payload controls explicit

Payload-heavy logging should be controlled separately from log level.
For example:

- `include_llm_payloads=false` by default
- `include_tool_payloads=summary` by default
- `include_command_output=summary` by default

Rationale:

- `debug` should not automatically dump entire prompts or megabytes of build output
- operators need predictable control over log size and sensitivity

## 10. Reuse existing summaries instead of inventing new ones

Where possible, live logs should reuse existing summarization logic already implicit in:

- `ToolCallRecord.input_summary`
- `ToolCallRecord.output_summary`
- `LlmCallRecord.request_summary`
- `LlmCallRecord.response_summary`
- `CodingAction.details`

This keeps live logs consistent with persisted artifacts.

## Proposed implementation phases

### Phase 1: live trace plumbing

Add central logging configuration and integrate Pydantic AI live event streaming as the primary tracing path.

Files likely involved:

- `aftk/cli.py`
- `aftk/conf/main.yaml`
- `aftk/logging.py` (new)
- `aftk/runner.py`
- role services or agent invocation sites where `event_stream_handler` can be attached
- tests for CLI config parsing / live trace emission

Deliverables:

- log config in Hydra
- `live_traces` and related trace controls
- event-stream handler(s) that emit model/tool/retry/final-result trace lines during the run
- console and file handlers writing traces to the terminal and `.aftk/cli.log`
- dependency logger suppression by default

### Phase 2: runner lifecycle logging

Instrument `aftk/runner.py` with INFO/DEBUG logs for:

- runner start/end
- run id allocation
- initializer/orchestrator/worker run boundaries
- decision validation / patch application / task creation
- attempt claim / finish / failure
- iteration count and completion summary

This phase complements live traces by giving higher-level framework context around the streamed agent events.

### Phase 3: task and coding service logging

Add logs in:

- `aftk/tasks/service.py`
- `aftk/coding/commands.py`
- `aftk/coding/filesystem.py`
- `aftk/coding/search.py`

Focus on:

- task state transitions
- command start/end, exit code, timeout
- file edits / reads / writes at debug level
- warnings for non-zero exits, edit conflicts, sandbox violations

### Phase 4: toolkit/client logging

Add framework-controlled logs around toolkit operations in:

- `aftk/agents/tools/toolkit.py`
- possibly `aftk_client/client.py`

Focus on:

- JSON-RPC method name
- path / line / col summaries
- typed errors (`FileNotOpenError`, `StaleNodeError`, etc.)
- session lifecycle (`open`, `close`, worker restarts)

These should default to debug so normal runs are not too noisy.

### Phase 5: structured event log

Add a lightweight structured event writer for exact timeline reconstruction.

Possible implementation:

- `aftk/storage/log_events.py` or `aftk/logging.py`
- append JSONL events with a stable schema
- write project-wide and/or per-run event files
- include streamed live trace events as well as framework lifecycle events

This should become the source of truth for "what happened when" at runtime.

### Phase 6: optional deeper graph-level tracing

If the first live trace integration is not sufficient, add deeper tracing using:

- `agent.iter()`
- node-level graph instrumentation
- richer classification of streamed part deltas / final-result boundaries

This phase is only for extra fidelity beyond the baseline live traces from `event_stream_handler` / `run_stream_events()`.

## Recommended log level semantics

### `warning`

Show only:

- retries
- non-zero command exits
- task blockers
- recoverable toolkit/client issues
- run failures

### `info`

Show `warning` plus:

- runner lifecycle
- role/run boundaries
- task selection and completion
- command start/end summaries
- artifact locations

This should be the default.

### `debug`

Show `info` plus:

- tool start/end summaries
- summarized args/results
- task patch details
- command stdout/stderr previews
- toolkit session lifecycle
- rollup / usage summaries

### Optional future `trace`

Only if needed later, add either:

- a custom `TRACE` level
- or payload toggles that effectively provide trace behavior

Recommendation: start with standard levels plus payload flags.

## Redaction and truncation policy

Default rules should include:

- never log API keys or auth headers
- truncate long prompt/tool payloads and command output in console logs
- keep structured event logs summarized by default
- allow explicit opt-in for fuller payload logging during local debugging

## Testing plan

Add tests covering:

1. CLI logging config parsing
2. default dependency logger suppression
3. `.aftk/cli.log` creation
4. runner lifecycle log emission
5. command/tool retry warning emission
6. structured event log schema and append behavior
7. payload truncation / redaction behavior

Prefer focused unit tests plus one integration-style CLI test that confirms a run produces human-meaningful framework logs rather than only `httpx` lines.

## Docs updates

Update user-facing docs to describe:

- available logging config knobs
- default log file locations
- recommended debug invocations
- how to correlate live logs with `.aftk/runs/run-*/` artifacts

Likely doc targets:

- `README.md`
- `docs/framework/overview.md`
- optionally a new `docs/framework/logging.md`

## Acceptance criteria

This work is complete when:

1. running `autoformalize` produces framework-owned logs without requiring any code changes by the user
2. the default CLI log is dominated by AFTK lifecycle events, not raw `httpx` request lines
3. live traces show agent activity while a run is still in progress, including tool calls and retries
4. an operator can identify the current role, run id, task id, and last meaningful action from the live log
5. debug mode reveals tool calls, retries, command execution details, and streamed agent events
6. logs can be made quieter or more verbose through Hydra config / overrides
7. structured persistent logs exist for exact runtime timelines
8. sensitive/raw payloads are not dumped by default

## Suggested implementation order

1. add central logging config + CLI surface with explicit live-trace controls
2. integrate Pydantic AI event streaming into agent execution for live traces
3. suppress noisy dependency logs by default
4. instrument runner lifecycle
5. instrument task and coding services
6. add structured event JSONL logs
7. optionally add deeper graph-level tracing if baseline live traces are still insufficient
