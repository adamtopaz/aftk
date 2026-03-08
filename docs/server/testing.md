# Server / file-worker testing

Run the full project suite with:

```text
lake test
```

Or run only the server suite with:

```text
lake exe aftk_server_test
```

## Test layout

The server tests live under `AFTKTest/Server/`:

```text
AFTKTest/Server/Assert.lean
AFTKTest/Server/Fixtures.lean
AFTKTest/Server/Protocol.lean
AFTKTest/Server/Worker.lean
AFTKTest/Server/Hub.lean
AFTKTest/Server/Integration.lean
AFTKTest/Server/Process.lean
AFTKTest/Server/Main.lean
```

Supporting fixtures live under:

```text
tests/server/fixtures/lean/
tests/server/fixtures/knowledgebase/
```

## Current coverage

### Protocol tests

- AFTK-specific error-code values
- representative JSON round trips for protocol result types
- hover JSON shape checks

### Direct worker tests

Against a one-shot worker context built directly from fixture Lean files:

- ordinary hover lookup
- term-goal lookup
- plain-goal lookup
- tactic-state capture and direct `simpa` execution

### Hub tests

- path normalization and identity resolution
- file-stamp reading
- file-stamp rejection for non-file paths

### Lower-layer integration tests

Against a Lean file containing `informal[...]` plus a fixture knowledge-base root:

- rich knowledge-base-backed hover at `informal[...]` sites

### End-to-end process tests

Using a real subprocess `aftk_server` and JSON-RPC requests over stdio:

- open/reuse/close/shutdown lifecycle
- hover, term-goal, plain-goal, load-node, get-goals, run-tactic flow
- `run_tactic_steps`
- invalid position parameter handling
- file-change invalidation (`-32011`)
- worker-unavailable behavior (`-32012`)
- stale-node behavior after reopen (`-32013`)

## Fixture files

### `tests/server/fixtures/lean/Semantics.lean`

Used for:

- ordinary hover
- plain term-goal queries
- proof-goal queries
- tactic-state capture
- tactic execution

### `tests/server/fixtures/lean/Informal.lean`

Used for:

- richer hover at a real `informal[...]` site

### `tests/server/fixtures/knowledgebase/basic-valid`

Used to resolve the `informal[...]` reference in the server integration fixture.

## Process-test harness

`AFTKTest.Server.Fixtures` provides a small reusable subprocess client that:

- starts `lake exe aftk_server`
- writes JSON-RPC request lines to stdin
- reads one response line per request from stdout
- parses/inspects result and error payloads
- cleans up the child process

This matters because many important server guarantees only exist at the process boundary.

## Why the end-to-end tests matter

The server layer has several behaviors that pure library tests cannot fully protect:

- real child-process spawning
- worker death detection
- session cleanup after invalidation
- file-change behavior across open workers
- JSON-RPC envelope compatibility

That is why the suite includes both direct worker/hub tests and subprocess tests.

## Good extension rule

When changing the server layer:

1. add/update a protocol test if the wire contract changes
2. add/update a direct worker or hub test if the change is internal-semantic
3. add/update a process test if lifecycle, invalidation, or JSON-RPC behavior changes
4. add/update an integration test if lower-layer hover/presentation behavior changes

## Current limitations reflected by the tests

The tests intentionally reflect the current v1 model rather than an aspirational incremental-LSP model:

- workers are one-shot snapshots
- file edits on disk require reopen
- transient tactic nodes are session-local and ephemeral

So if the implementation later moves toward incremental editable documents, this suite will need deliberate updates rather than silent drift.
