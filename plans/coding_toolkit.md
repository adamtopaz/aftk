# Plan: Pi-style coding toolkit for Pydantic AI

## Goal

Create a second Pydantic AI toolkit that exposes **local coding tools** analogous to the built-in
Pi coding-agent tools:

- reading files
- writing files
- editing files
- running shell commands
- searching file contents
- finding files by glob
- listing directories

The new toolkit should fit this repository's current direction:

- live under `aftk/toolkits/`
- be implemented **directly for Pydantic AI agents**, not as a framework-agnostic abstraction
- use the same **non-throwing tool failure** philosophy as `AftkToolkit`
- optimize for a clean experimental API rather than compatibility baggage

Because this repo is still **PRE-RELEASE** and **EXPERIMENTAL**, internal consistency matters more
than matching every historical choice exactly.

---

## Research findings: what Pi ships today

I read the relevant Pi docs and examples:

- `README.md`
- `docs/sdk.md`
- `docs/extensions.md`
- `docs/packages.md`
- `examples/sdk/05-tools.ts`

I also inspected Pi's built-in tool implementations in:

- `dist/core/tools/index.js`
- `dist/core/tools/read.*`
- `dist/core/tools/bash.*`
- `dist/core/tools/edit.*`
- `dist/core/tools/write.*`
- `dist/core/tools/grep.*`
- `dist/core/tools/find.*`
- `dist/core/tools/ls.*`
- `dist/core/tools/truncate.*`
- `dist/core/tools/path-utils.*`

### Built-in tool sets in Pi

Pi exposes three practical built-in groupings:

1. **Default coding tools**
   - `read`
   - `bash`
   - `edit`
   - `write`

2. **Read-only tools**
   - `read`
   - `grep`
   - `find`
   - `ls`

3. **All built-in tools**
   - `read`
   - `bash`
   - `edit`
   - `write`
   - `grep`
   - `find`
   - `ls`

Pi's SDK also exposes per-tool factory functions so each tool can be bound to a specific `cwd`.
That is an important design cue for us: **relative paths should resolve against a configured root**,
not implicitly against whatever the current Python process happens to be doing.

### Built-in tool behavior in Pi

| Tool | Main inputs | Key Pi behavior |
|------|-------------|-----------------|
| `read` | `path`, `offset`, `limit` | Reads text files; supports images too; text output is truncated to first 2000 lines or 50KB; supports continuation with `offset` |
| `write` | `path`, `content` | Creates parent directories; overwrites file |
| `edit` | `path`, `oldText`, `newText` | Exact/surgical replacement; requires unique match; returns diff details |
| `bash` | `command`, `timeout` | Runs in configured cwd; returns stdout+stderr; truncates to last 2000 lines or 50KB; saves full output to a temp file when truncated |
| `grep` | `pattern`, `path`, `glob`, `ignoreCase`, `literal`, `context`, `limit` | Searches contents; respects `.gitignore`; truncates long lines and total output |
| `find` | `pattern`, `path`, `limit` | Glob-based file search; respects `.gitignore`; returns relative paths |
| `ls` | `path`, `limit` | Lists directory contents; includes dotfiles; directories get `/` suffix |

### Important implementation details worth mirroring

From Pi's source, the important semantics are:

- shared truncation defaults:
  - `DEFAULT_MAX_LINES = 2000`
  - `DEFAULT_MAX_BYTES = 50 * 1024`
- grep line truncation:
  - `GREP_MAX_LINE_LENGTH = 500`
- `read` truncates from the **head**
- `bash` truncates from the **tail**
- `grep`, `find`, and `ls` are also bounded by output size, not just result count
- paths are resolved relative to a configured cwd
- `~` expansion is supported
- Pi strips a leading `@` from paths in its path resolver
- `edit` preserves BOM/line endings and rejects ambiguous replacements

### Deliberate differences we probably want

Pi is a terminal harness with custom tool plumbing and rich UI. Our Python toolkit should be
**analogous**, not a literal copy.

In particular:

1. **Tool failures should not escape as exceptions.**
   In this repo, expected failures should be returned to the agent in-band.

2. **We should not auto-download external binaries.**
   Pi can download `rg`/`fd`; our Python package should avoid surprising runtime downloads.

3. **Text-first v1 is enough.**
   Pi's `read` supports images, but our first pass can focus on text files. We can revisit image
   support later if we decide how we want Pydantic AI tool returns to carry binary content.

4. **Structured success payloads are preferable to raw strings.**
   Pi's tools are optimized for a TUI. Our toolkit should optimize for agent reasoning.

---

## High-level design choice

Implement a public `CodingToolkit` as a **`WrapperToolset[Any]`** over one or more internal
`FunctionToolset`s, following the same pattern we already used for `AftkToolkit`.

That gives us:

- normal Pydantic AI schema generation from Python methods
- a single place to catch expected filesystem/shell/search failures
- easy filtering for read-only vs mutating tool profiles
- consistent metadata such as `mutates`, `source`, and `sequential`

### Why not a totally separate custom tool framework?

We already have a good pattern in this repo:

- a Pydantic-AI-specific toolkit package
- wrapper-level failure mapping
- Pydantic input models
- sequential execution for stateful/mutating tools

The coding toolkit should extend that pattern, not reinvent it.

---

## Proposed public API

```python
from aftk.toolkits.coding import CodingToolkit

toolkit = CodingToolkit(cwd=repo_root)
```

Proposed constructor:

```python
class CodingToolkit(WrapperToolset[object]):
    def __init__(
        self,
        *,
        cwd: str | Path | None = None,
        read_only: bool = False,
        include_search: bool = True,
        follow_gitignore: bool = True,
        id: str | None = None,
    ) -> None: ...
```

### Meaning of the options

- `cwd`
  - base directory for relative path resolution
  - defaults to `Path.cwd()` if omitted
- `read_only`
  - excludes `bash`, `edit`, and `write`
  - keeps `read` plus read-only discovery/search tools
- `include_search`
  - when `True`, expose `grep`, `find`, and `ls`
  - when `False`, expose only the core coding tools
- `follow_gitignore`
  - whether `grep` and `find` should skip ignored files
- `id`
  - optional Pydantic AI toolset id

### Resulting tool profiles

- `CodingToolkit(read_only=False, include_search=False)`
  - Pi-like default coding set: `read`, `bash`, `edit`, `write`
- `CodingToolkit(read_only=True, include_search=True)`
  - Pi-like read-only set: `read`, `grep`, `find`, `ls`
- `CodingToolkit(read_only=False, include_search=True)`
  - full set of all seven tools

For this repo, I would make `include_search=True` the default, since users asking for a coding
toolkit generally want search/discovery too.

---

## Proposed module layout

```text
aftk/
  toolkits/
    coding/
      __init__.py
      _toolkit.py
      models.py
      errors.py
      _path_utils.py
      _truncate.py
      _read.py
      _write.py
      _edit.py
      _bash.py
      _search.py      # grep, find, ls helpers
```

Possible public exports:

- `CodingToolkit`
- `CodingToolErrorInfo`
- `CodingToolFailure`
- `CodingToolSuccess`
- `CodingToolResult`

### Packaging

This toolkit is specifically for Pydantic AI. We should therefore implement it on top of the
package's normal `pydantic-ai` dependency, not behind an optional extra, missing-dependency import
shim, or alternate install path.

Likely dependency updates:

- rely on the package's normal `pydantic-ai>=1,<2` dependency
- add `pathspec` as a normal runtime dependency if we use it for `.gitignore` handling
- add the same packages to the dev dependency group for tests/type-checking as needed

### Dependency stance to avoid another cleanup later

To avoid repeating the cleanup we had to do for `AftkToolkit`, the coding toolkit should:

- import Pydantic AI directly in `aftk/toolkits/coding/__init__.py` and related modules
- avoid `try/except ModuleNotFoundError` wrappers that describe `pydantic-ai` as optional
- avoid README/docs instructions that tell users to install a separate extra just to use `CodingToolkit`
- avoid a `[project.optional-dependencies]` entry whose only purpose is enabling the coding toolkit

The important design point here is not dependency minimization; it is that the coding toolkit is a
first-class Pydantic AI toolset for agent use in this repository.

---

## Proposed tool surface

Use the **same tool names as Pi** where practical:

- `read`
- `write`
- `edit`
- `bash`
- `grep`
- `find`
- `ls`

That makes prompt patterns and agent habits more portable.

### 1. `read`

Proposed inputs:

- `path: str`
- `offset: int | None`
- `limit: int | None`

Mirror Pi semantics closely:

- resolve path relative to `cwd`
- support `~` expansion
- support stripping a leading `@`
- text-only in v1
- truncate from the head at 2000 lines / 50KB
- if the user passes `limit`, include a continuation hint when more lines remain
- if a single line exceeds the byte budget, return a clear hint to use `bash`

Proposed success payload:

- `text`
- `start_line`
- `end_line`
- `total_lines`
- `truncation`

### 2. `write`

Proposed inputs:

- `path: str`
- `content: str`

Semantics:

- resolve relative to `cwd`
- create parent directories automatically
- overwrite existing file

Proposed success payload:

- `path`
- `bytes_written`
- `created_parent_directories: bool`

### 3. `edit`

Proposed inputs:

- `path: str`
- `oldText: str`
- `newText: str`

Use camelCase aliases so the generated schema stays Pi-like.

Semantics:

- resolve relative to `cwd`
- require a unique match
- preserve BOM and line endings
- reject missing match or ambiguous match
- generate a unified diff

Proposed success payload:

- `path`
- `diff`
- `first_changed_line`

### 4. `bash`

Proposed inputs:

- `command: str`
- `timeout: int | None`

Semantics:

- run in configured `cwd`
- capture stdout and stderr together
- truncate from the tail at 2000 lines / 50KB
- if truncated, save full output to a temp file and return that path
- non-zero exit should become a structured failure, not an uncaught exception
- timeout should become a structured failure with `retryable=True`

Proposed success payload:

- `text`
- `exit_code` (normally `0`)
- `truncation`
- `full_output_path`

### 5. `grep`

Proposed inputs:

- `pattern: str`
- `path: str | None`
- `glob: str | None`
- `ignoreCase: bool | None`
- `literal: bool | None`
- `context: int | None`
- `limit: int | None`

Semantics:

- support file or directory search roots
- return relative paths plus line numbers
- support literal vs regex search
- support context lines
- truncate lines to 500 chars with a note
- enforce a default match limit of 100
- respect `.gitignore` when `follow_gitignore=True`
- skip unreadable/binary files safely

Proposed success payload:

- `text`
- `matches_returned`
- `match_limit_reached`
- `lines_truncated`
- `truncation`

### 6. `find`

Proposed inputs:

- `pattern: str`
- `path: str | None`
- `limit: int | None`

Semantics:

- glob-based recursive search
- return paths relative to the search root
- default limit 1000
- respect `.gitignore` when enabled

Proposed success payload:

- `text`
- `results_returned`
- `result_limit_reached`
- `truncation`

### 7. `ls`

Proposed inputs:

- `path: str | None`
- `limit: int | None`

Semantics:

- list directory contents
- include dotfiles
- sort case-insensitively
- add `/` suffix to directories
- default limit 500

Proposed success payload:

- `text`
- `entries_returned`
- `entry_limit_reached`
- `truncation`

---

## Failure model

Expected failures should be converted into structured tool results rather than escaping.

Proposed envelope types:

```python
class CodingToolErrorInfo(BaseModel):
    kind: str
    message: str
    retryable: bool
    suggested_action: str | None = None
    details: dict[str, Any] | None = None

class CodingToolSuccess(BaseModel):
    ok: Literal[True] = True
    tool: str
    data: Any

class CodingToolFailure(BaseModel):
    ok: Literal[False] = False
    tool: str
    error: CodingToolErrorInfo
```

### Likely failure kinds

- `file_not_found`
- `path_not_found`
- `not_a_directory`
- `permission_denied`
- `decode_error`
- `invalid_pattern`
- `text_not_found`
- `ambiguous_edit`
- `no_change`
- `command_failed`
- `timeout`
- `tool_internal_error`

The wrapper should catch the expected Python exceptions and map them into these stable kinds.

---

## Search backend strategy

Pi uses `rg` and `fd`, but we should not depend on runtime binary downloads.

### Recommended v1 strategy

Implement `grep` and `find` in **pure Python**:

- recursive walk via `pathlib` / `os.scandir`
- glob filtering via `fnmatch` / `glob`
- `.gitignore` filtering via `pathspec`
- nested `.gitignore` support via cached specs per directory

### Why this is a good fit here

- no runtime download logic
- deterministic Python-side behavior in tests
- no system dependency on `rg`/`fd`
- easier packaging for a Python client library

### Possible later optimization

If performance becomes a problem on large repos, we can later add:

- optional acceleration via installed `rg` / `fd`
- but still keep the pure-Python path as the baseline implementation

---

## Execution policy and metadata

All tools should be marked **sequential**.

Reasoning:

- `edit`, `write`, and `bash` can mutate the filesystem arbitrarily
- even `read`, `grep`, `find`, and `ls` should observe a stable ordering relative to prior writes
- keeping all tools sequential matches the conservative policy we already chose for `AftkToolkit`

Tool metadata should include at least:

- `source="coding"`
- `layer="filesystem"` or `layer="shell"`
- `mutates=True/False`
- `read_only=True/False`

---

## Important implementation details

### Path handling

Implement a shared helper that:

- expands `~`
- strips a leading `@`
- resolves relative paths against `cwd`
- returns normalized absolute paths internally

We do **not** need to port every Pi path quirk in v1 (for example the macOS screenshot Unicode
fallback logic). The important part is stable cwd-relative behavior.

### Truncation helpers

Implement shared truncation helpers analogous to Pi's:

- head truncation for `read`
- tail truncation for `bash`
- byte-bounded output helpers for `grep`, `find`, `ls`
- single-line truncation helper for `grep`

### Edit behavior

Use a focused implementation:

- exact match first
- preserve BOM and original line endings
- reject multiple matches
- diff via `difflib.unified_diff`

We do not need to reimplement every fuzzy edge case from Pi unless testing shows a real need.

### Shell execution

Use `asyncio.create_subprocess_exec`.

Preferred shell resolution:

- use `$SHELL` if available
- otherwise a sensible Unix fallback (`/bin/bash` or `/bin/sh`)

That is close enough to Pi for our purposes.

---

## Recommended implementation order

### Phase 1: shared scaffolding

1. Add `aftk/toolkits/coding/` package skeleton.
2. Use the package's normal `pydantic-ai` dependency and add `pathspec` as a normal dependency if the runtime search implementation needs it.
3. Add common result/error models.
4. Add shared path and truncation helpers.

### Phase 2: core file tools

5. Implement `read`.
6. Implement `write`.
7. Implement `edit`.
8. Implement `ls`.

### Phase 3: shell + search

9. Implement `bash`.
10. Implement Python-native `grep`.
11. Implement Python-native `find`.

### Phase 4: toolkit assembly

12. Implement `CodingToolkit(WrapperToolset[Any])`.
13. Register tools with profile filtering (`read_only`, `include_search`).
14. Mark tools sequential and attach metadata.
15. Add structured failure mapping in the wrapper.

### Phase 5: docs + tests

16. Add `tests/python/test_coding_toolkit.py`.
17. Update `README.md` with usage examples.
18. Run format/lint/type-check/tests.

---

## Test plan

Add focused Python tests covering both schema exposure and real behavior.

### Schema / exposure tests

- default tool exposure
- `read_only=True` removes mutating tools
- `include_search=False` removes `grep`/`find`/`ls`
- all tools are sequential
- metadata flags are present

### Read / write / edit tests

- read returns full small file
- read truncates large file with continuation hint
- read offset/limit behavior
- write creates parent directories
- edit successful unique replacement
- edit fails for missing text
- edit fails for ambiguous text
- edit preserves line endings

### Bash tests

- successful command
- non-zero exit becomes `CodingToolFailure`
- timeout becomes `CodingToolFailure`
- long output truncation plus full-output temp path

### Search tests

- grep literal and regex modes
- grep context lines formatting
- grep line truncation behavior
- grep limit behavior
- find glob matching
- ls sorting and directory suffix behavior
- `.gitignore` filtering for grep/find

### Integration-style tests

- use a temporary directory tree with nested folders and ignored files
- exercise a realistic agent workflow:
  - `find` a file
  - `read` it
  - `edit` it
  - `bash` test command
  - `grep` verify change

### Validation commands

- `uv run python -m unittest tests.python.test_coding_toolkit -v`
- `uv run python -m unittest discover -s tests/python -v`
- `uv run ruff check aftk tests/python/test_coding_toolkit.py`
- `uv run pyright`

---

## Deliberate non-goals for v1

To keep the first pass small and reliable, do **not** try to do all of this at once:

- Pi-style image attachment support in `read`
- auto-downloading `rg` / `fd`
- streaming partial `bash` updates into the UI
- remote/sandbox backends
- approval workflows for dangerous commands
- heavy shared abstraction refactors across all toolkits

If we later add more toolkits and see obvious duplication, we can extract shared toolkit helpers in a
follow-up pass.

---

## Recommended final shape

Implement a new Pydantic AI toolkit:

```python
from aftk.toolkits.coding import CodingToolkit
```

with Pi-like tool names:

- `read`
- `write`
- `edit`
- `bash`
- `grep`
- `find`
- `ls`

and AFTK-style runtime behavior:

- structured success/failure envelopes
- no expected tool failure should kill the agent run
- sequential execution
- cwd-relative, agent-friendly behavior
- direct Pydantic AI imports and normal package dependencies, not optional-extra shims

That gives us a strong general-purpose coding toolkit to pair with `AftkToolkit`, and it does so in
a way that is consistent with the rest of this repository.
