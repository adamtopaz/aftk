# Plan: worker coding tools for the framework

## Goal

Implement deterministic local coding tools that the framework runner can expose to **worker agents** for actual project work.
These tools are the mechanism by which workers can:

- search through files in the project directory
- read local files and relevant slices
- write or edit code
- run local validation commands such as `lake build`

These tools are intentionally **not** part of the orchestrator surface.
The orchestrator plans work; workers execute it.

## Architectural role

The framework has two different tool families:

1. **toolkit tools**
   - backed by `aftk_client.AsyncAftkClient`
   - knowledge-base, informal, and transient Lean queries
2. **coding tools**
   - backed by deterministic local filesystem and subprocess services
   - project search, file reads, code edits, and local command execution

That distinction matters.
The toolkit tools interact with the implemented AFTK layers.
The coding tools interact with the user's local project workspace.

## Core policy

The coding-tool policy for v1 should be:

- **worker agents get coding tools**
- **initializer and orchestrator do not get coding tools**
- all coding tools are sandboxed to the project root
- writes are blocked outside the project root
- framework-owned state under `.aftk/` is not editable through worker coding tools
- all command executions and file edits are logged

This keeps the planner/executor boundary explicit.

## Why this needs its own plan

The coding tools are where the framework starts to perform real side effects.
That means they need a clearer design than ordinary read-only query tools.

In particular, we need to define:

- which roles get which tools
- what file operations are allowed
- what commands are allowed
- how project-root sandboxing works
- how edits and command runs are logged for audit

## Non-goals for v1

The first version does not need to provide:

- arbitrary host-wide shell access
- network access through command execution
- writing outside the project root
- direct mutation of `.aftk/` state by workers
- file deletion or large-scale refactors driven by generic shell commands
- a full IDE/editor abstraction

The goal is controlled code work, not unrestricted machine access.

## Recommended package split

The implementation should separate deterministic services from agent tool wrappers.

```text
aftk/
  coding/
    __init__.py
    models.py
    filesystem.py
    search.py
    commands.py
  agents/
    tools/
      coding.py
```

Recommended responsibilities:

- `aftk/coding/models.py`
  - Pydantic models for search hits, edit results, and command results
- `aftk/coding/filesystem.py`
  - path validation, reads, writes, and structured edits
- `aftk/coding/search.py`
  - project-root file enumeration and text search
- `aftk/coding/commands.py`
  - command execution, timeouts, cwd validation, stdout/stderr capture
- `aftk/agents/tools/coding.py`
  - pydantic-ai tool registration for worker-facing coding tools

This preserves the principle that deterministic Python code owns the side effects.

## Relevant pydantic-ai docs for coding-tool wrappers

When implementing `aftk/agents/tools/coding.py`, keep these docs handy:

- [Function Tools](https://ai.pydantic.dev/tools/index.md) — `@agent.tool`, `@agent.tool_plain`, tool schemas, and docstring-derived parameter descriptions
- [Toolsets](https://ai.pydantic.dev/toolsets/index.md) — composing worker-only tool bundles and swapping them at agent construction, run time, or in overrides
- [Testing](https://ai.pydantic.dev/testing/index.md) — `TestModel`, `FunctionModel`, and `Agent.override(...)` for role-restriction and tool-wiring tests

Implementation note from the Function Tools docs:

- tool schemas come from Python signatures and docstrings
- every worker coding tool should therefore have a precise docstring, clear parameter descriptions, and a small typed return model

## Permission model

### Role scoping

The runner should construct different toolsets per role.

#### Initializer

Allowed:

- project summary/read tools
- toolkit query tools

Not allowed:

- file mutation
- project-directory search as a coding tool
- command execution

#### Orchestrator

Allowed:

- task-state inspection
- project summaries and other read-oriented context
- toolkit query tools

Not allowed:

- file mutation
- project-directory search as a coding tool
- command execution such as `lake build`

#### Worker

Allowed:

- toolkit query tools
- project search tools
- file read tools
- file write/edit tools
- command execution tools
- convenience validation tools such as `lake build`

Not allowed:

- direct task-graph mutation
- writes outside the project root
- writes to `.aftk/`

## Path and sandbox model

All coding tools should resolve paths relative to the framework's configured `project_root`.

Recommended rules:

- accept relative paths as the default API
- normalize and resolve paths before use
- reject any path that escapes the project root
- reject symlink-based escapes
- reserve `.aftk/` from worker mutation
- consider `.git/`, `.lake/build/`, and similar generated directories read-only or excluded from ordinary search by default

This should be enforced in deterministic Python code, not left to prompt instructions.

## Tool surface for v1

The worker coding surface should be explicit and fairly small.

### 1. File search tools

Workers need a way to find relevant code.

Recommended tools:

```text
list_project_files(
  include_globs: list[str] | None,
  exclude_globs: list[str] | None,
  limit: int = 200,
) -> list[ProjectPath]

search_project_text(
  query: str,
  include_globs: list[str] | None,
  exclude_globs: list[str] | None,
  limit: int = 100,
) -> list[SearchMatch]
```

Recommended behavior:

- default to searching user-authored project files, not generated build outputs
- return short snippets with line numbers
- keep result sizes bounded

### 2. File read tools

Workers need structured reads, not only raw whole-file dumps.

Recommended tools:

```text
read_file(path: str) -> FileReadResult
read_file_slice(path: str, start_line: int, end_line: int) -> FileReadResult
```

Recommended behavior:

- include normalized path in the result
- include line ranges for slices
- keep very large reads bounded or paginated

### 3. File write/edit tools

Workers need to create and modify code.

Recommended tools:

```text
write_file(path: str, content: str, overwrite: bool = False) -> FileWriteResult
replace_in_file(path: str, old_text: str, new_text: str) -> FileEditResult
append_to_file(path: str, content: str) -> FileEditResult
```

Recommended policy:

- prefer **structured or surgical edits** over full rewrites when modifying existing files
- allow full writes for new files or explicit complete replacements
- fail loudly if `replace_in_file` does not match exactly once
- return enough metadata for audit logs

A future patch-based edit API can be added later if needed.

### 4. Command execution tools

Workers need to validate and inspect the project after edits.

Recommended tools:

```text
run_command(
  argv: list[str],
  cwd: str | None = None,
  timeout_seconds: float | None = None,
) -> CommandResult

lake_build(
  target: str | None = None,
  timeout_seconds: float | None = None,
) -> CommandResult
```

Recommended behavior:

- run only within the project root or an allowed subdirectory
- capture exit code, stdout, stderr, and duration
- enforce timeouts
- log every command invocation
- provide a dedicated `lake_build` convenience tool because it is a core validation step for Lean work

For v1, it is reasonable to keep command execution narrower than unrestricted shell access.
A curated allowlist or policy layer may be appropriate.

## Recommended result models

A few typed result models will make these tools easier to use and audit.

```text
ProjectPath
  path: str

SearchMatch
  path: str
  line: int
  column: int | None
  snippet: str

FileReadResult
  path: str
  content: str
  start_line: int | None
  end_line: int | None

FileWriteResult
  path: str
  created: bool
  overwritten: bool
  bytes_written: int

FileEditResult
  path: str
  changed: bool
  replacement_count: int

CommandResult
  argv: list[str]
  cwd: str
  exit_code: int
  stdout: str
  stderr: str
  duration_seconds: float
  timed_out: bool
```

These should stay simple and machine-friendly.

## Logging and audit

Because coding tools cause side effects, every worker run should persist a coding-action log.
These coding-action logs should also align with the broader framework-wide tool-call logging, rather than existing as an isolated audit trail.

Recommended log contents:

- file reads above some threshold only if we want full audit, otherwise just mutations
- all file writes and edits
- all command executions
- timestamps
- normalized paths
- command exit codes and durations
- task/run association so coding actions line up with task attempts and broader tool-call logs

A practical layout is:

```text
.aftk/
  runs/
    <run-id>/
      result.json
      messages.json
      llm-calls.jsonl
      tool-calls.jsonl
      usage.json
      cost.json
      coding-actions.jsonl
```

The exact layout can evolve, but the principle should not:

- worker side effects are auditable

## Interaction with task execution

The intended worker loop is:

1. inspect the task brief
2. search for relevant files
3. read the local context
4. use toolkit tools as needed for Lean/informal/knowledge-base insight
5. edit code
6. run validation commands such as `lake build`
7. report outcome and evidence

This makes coding tools a core part of worker execution, not an optional afterthought.

## Validation expectations

The framework should encourage workers to validate their changes before claiming completion.

For Lean-oriented tasks, the default validation path should usually include:

- `lake build`

Depending on the task, additional commands may later be useful, but `lake build` is the key v1 requirement.

## Safety and failure behavior

The coding layer should fail clearly and structurally.

Examples:

- path escapes project root -> explicit sandbox error
- write to reserved path -> explicit permission error
- edit text not found -> explicit edit failure
- command timeout -> explicit timeout result
- command exits nonzero -> structured command result, not silent failure

Workers and the runner should be able to distinguish:

- tool failure
- validation failure
- task-level blockage

## Testing plan

### 1. Filesystem safety tests

Test:

- path normalization
- root-escape rejection
- symlink-escape rejection
- `.aftk/` write rejection

### 2. Search tests

Test:

- project search returns expected matches
- excluded directories are skipped by default
- result limits are enforced

### 3. Edit tests

Test:

- new-file writes
- exact-text replacement success
- replacement failure when text is missing
- append behavior

### 4. Command tests

Test:

- command execution inside the project root
- cwd restriction
- timeout handling
- logging of stdout/stderr/exit code
- `lake_build()` wrapper behavior

### 5. Integration tests with worker runs

Use a fixture Lean project and test:

- worker searches for a file
- worker edits a file
- worker runs `lake build`
- coding-action logs are persisted
- orchestrator still has no access to these tools

## Suggested implementation phases

### Phase 1: deterministic coding services

- add `aftk/coding/models.py`
- add `aftk/coding/filesystem.py`
- add `aftk/coding/search.py`
- add `aftk/coding/commands.py`
- implement project-root sandboxing

### Phase 2: worker-facing pydantic-ai tool wrappers

- add `aftk/agents/tools/coding.py`
- expose typed worker tools for search, read, edit, and commands
- keep tool registration role-scoped

### Phase 3: logging and runner integration

- persist coding-action logs under `.aftk/runs/`
- integrate coding-action logs with the broader tool-call log format used by the framework
- wire worker toolsets through the runner
- ensure initializer and orchestrator do not receive coding tools

### Phase 4: integration and fixture tests

- add filesystem, search, edit, and command tests
- add fixture-project worker tests using `lake build`

## Acceptance criteria

The coding tools are ready when all of the following are true:

- worker agents can search project files, read files, edit code, and run `lake build`
- initializer and orchestrator do not receive coding tools
- all coding actions are sandboxed to the project root
- worker coding actions are logged for audit
- coding-tool actions appear in the broader framework tool-call logs
- command execution has timeouts and structured results
- fixture tests cover an edit-and-build workflow end to end
