# Server/File-Worker Testing Design

## Status

Component plan and implementation-status document for testing the server/file-worker layer.
This document refines the overall server-layer plan in `plans/server.md` and works together with `plans/server/transport.md`, `plans/server/protocol.md`, `plans/server/hub.md`, `plans/server/worker.md`, `plans/server/lean-integration.md`, `plans/server/integration.md`, and `plans/server/layout.md`.

## Component implementation status

- Overall status: Implemented
- Implemented in code: Yes
- Last updated basis: the repository now has `AFTKTest/Server/*`, checked-in server fixtures, direct worker/hub tests, and subprocess end-to-end coverage integrated into `lake test`.

## Purpose

This document defines how the server/file-worker layer should be tested.
It covers:

- shared protocol/transport tests
- direct worker semantic tests
- hub lifecycle tests
- subprocess end-to-end tests
- lower-layer integration tests for hover behavior
- and how this layer should fit into `lake test`

The goal is to make testing part of the design of the layer rather than something added only after long-running process behavior has already become hard to reason about.

## Design goals

Testing for this layer should:

- validate reusable library behavior below the executable wrappers
- validate the process boundaries as real operational surfaces, not just as pure functions
- cover both successful and intentionally failing lifecycle cases
- test transient proof-state invalidation explicitly
- validate lower-layer-aware hover behavior on real fixture files
- remain deterministic enough for frequent local use
- fit cleanly into the project’s existing `lake test` workflow

## Scope and non-scope

### In scope

- direct library tests for protocol types and worker query logic
- subprocess tests for hub/worker processes and JSON-RPC behavior
- file-change and worker-death invalidation cases
- lower-layer integration tests for `informal[...]` hover/presentation behavior
- test-tree and fixture layout recommendations

### Out of scope

- continuous-integration service setup details
- benchmarking or performance measurement
- exhaustive golden coverage for every Lean-generated hover string across all future Lean versions

## Core testing principles

### 1. Test the library below the processes

The server layer is not just two executables.
It also contains reusable library logic such as:

- protocol types
- transport helpers
- hub lifecycle helpers
- worker context/query/tactic-state logic

Those pieces should be tested directly where practical, not only through end-to-end subprocesses.

### 2. Still test the actual processes

Because this layer exists to provide long-running operational behavior, pure tests are not enough.
The test suite must also spawn and exercise:

- `aftk_server`
- and `aftk_file_worker`

through their real stdio JSON-RPC boundaries.

### 3. Treat invalidation behavior as a first-class contract

The most important operational failures are not incidental; they are part of the layer’s design.
Tests must therefore explicitly cover:

- unopened-file failures
- file-changed invalidation
- worker-unavailable failures
- stale node ids after restart/reopen
- tactic failure vs stale-node failure distinctions

### 4. Test lower-layer integration against real lower-layer fixtures

The server layer’s value in AFTK is not just Lean parity.
It must also integrate with the knowledge-base and informal layers.
That means tests should exercise hover behavior over real `informal[...]` sites backed by real fixture knowledge-base roots.

### 5. Prefer structural assertions for machine-facing JSON

The public protocol is a stronger compatibility boundary than exact pretty-printed human text.
Therefore:

- JSON envelopes and field shapes should receive strong structural assertions
- human-facing text should still be tested, but usually with focused substring/section assertions unless exact formatting is itself part of the contract

### 6. Add process tests incrementally with implementation phases

The testing plan should not mean “write all tests at the very end.”
Instead:

- add harness pieces early
- add tests alongside each implementation phase
- add regression cases whenever an operational bug appears

## Recommended test layout

A practical initial test layout is:

```text
AFTKTest/Server.lean
AFTKTest/Server/Assert.lean
AFTKTest/Server/Fixtures.lean
AFTKTest/Server/Protocol.lean
AFTKTest/Server/Worker.lean
AFTKTest/Server/Hub.lean
AFTKTest/Server/Integration.lean
AFTKTest/Server/Process.lean
AFTKTest/Server/Main.lean
tests/server/fixtures/lean/...
tests/server/fixtures/knowledgebase/...
tests/server/golden/...
```

This splits the suite into:

- direct library/domain tests
- integration tests against lower-layer fixtures
- and real process-boundary tests

## Lake target strategy

The project already has an aggregate test driver executable.
The server-layer suite should fit into that workflow under:

```text
lake test
```

A good initial approach is:

- add `AFTKTest/Server/Main.lean` as a server-suite runner
- re-export it from `AFTKTest/Server.lean`
- update the package-level `AFTKTest.Main` driver to run:
  - the knowledge-base suite,
  - the informal suite,
  - and the server suite

The user-facing goal should remain one project-level test entrypoint.

## Test harness design

The first implementation does not need an external testing framework.
A small project-local harness parallel to the existing lower-layer suites is sufficient.

### Recommended harness features

The server-layer harness should provide helpers such as:

- `assertEq`
- `assertTrue` / `assertFalse`
- `assertSome` / `assertNone`
- `assertContains`
- `assertJsonField` or structural JSON comparison helpers
- subprocess helpers for launching Lean executables
- helpers for sending one JSON-RPC request and reading one response line
- helpers for temporary-file and temporary-directory setup/cleanup
- helpers for waiting with timeouts and reporting process failures clearly

## Fixture strategy

This layer needs multiple kinds of fixtures.

### 1. Lean source fixtures

Use checked-in Lean files under something like:

```text
tests/server/fixtures/lean/
```

These should include cases such as:

- simple hover/query file
- file with tactic blocks suitable for `load_node`
- file with multiple goals at one location
- file with `informal[...]` occurrences
- file importing the necessary lower-layer modules and knowledge-base-root option

### 2. Knowledge-base fixtures for lower-layer integration

Use real knowledge-base roots under something like:

```text
tests/server/fixtures/knowledgebase/
```

These can often reuse or mirror the informal-layer fixture roots.
The important point is that hover integration tests run against real node content.

### 3. Golden files

Use checked-in golden files under:

```text
tests/server/golden/
```

for cases where exact emitted text or JSON matters, especially:

- representative JSON-RPC response envelopes
- stable `shutdown`/lifecycle response examples
- selected plain-goal rendering examples if exact format is treated as part of the contract for one Lean version

### 4. Temporary mutable copies

Any test that mutates files—especially file-change invalidation tests—should operate on temporary copies of fixture files rather than on the checked-in originals.

## Recommended test categories

## 1. Protocol tests

These should test:

- JSON codec round-trips for shared request/response types
- required vs optional field behavior
- stable error-code mapping
- representative envelope shapes for success and error responses

## 2. Direct worker semantic tests

These should test the worker logic below the subprocess boundary where practical.
Examples:

- building a worker context from a fixture file
- `get_hover` on ordinary Lean sites
- `get_plain_goal` and `get_plain_term_goal`
- `load_node` and resulting id counts
- `get_goals` and `run_tactic` over direct worker state

Direct worker tests are especially useful for fast iteration because they avoid process startup overhead.

## 3. Hub lifecycle tests

These should test hub logic below full end-to-end process orchestration where practical.
Examples:

- path normalization and identity lookup
- file-stamp change detection
- session-registry state changes
- close/shutdown cleanup helpers
- per-session serialization behavior

## 4. End-to-end process tests

These should spawn a real hub process and drive it over stdio JSON-RPC.
Core cases should include:

- `open` then simple semantic query
- repeated `open` returns `opened = false` for fresh session reuse
- `close` on open and unopened files
- `shutdown` with zero and nonzero session counts
- `load_node` -> `get_goals` -> `run_tactic`
- `run_tactic_steps`

## 5. File-change invalidation tests

These should:

1. open a temporary copy of a fixture file
2. issue at least one successful query
3. modify the file on disk
4. verify that the next file-scoped request returns `-32011`
5. reopen the file
6. verify that requests succeed again
7. verify that pre-change node ids now fail with stale-node error

This category is especially important because reopen-on-change is a settled v1 design choice.

## 6. Worker-unavailable tests

These should simulate or induce worker death and verify that the hub returns `-32012` and cleans up the session.
Possible strategies include:

- terminating the worker subprocess from the test harness if practical
- or using a dedicated test-only worker behavior that exits on command if a lightweight mechanism is added later

## 7. Lower-layer integration tests

These should exercise hover over `informal[...]` sites and verify at least:

- compact summary information appears
- richer preview-style presentation appears when the worker recognizes the site
- the result is derived from the configured fixture knowledge-base root
- ordinary Lean hover still works on non-informal sites in the same file

## 8. Negative request tests

These should cover cases such as:

- malformed JSON-RPC envelopes
- unknown methods
- invalid params like `line = 0` or `col = 0`
- unopened-file requests
- stale/unknown node ids
- tactic parse failure
- tactic execution failure

## Assertions for human-facing text

The suite should be selective about exact-text assertions.

### Good exact-text or near-exact candidates

- small protocol/golden envelopes
- `shutdown` result shape
- selected compact informal summary rendering if intentionally deterministic

### Better substring/section assertions

- generic hover text from Lean
- pretty-printed goals that may shift slightly across Lean versions
- tactic failure prose

For those cases, tests should usually assert the presence of key facts rather than every whitespace detail.

## Process test client helper

The server-layer tests should include a small client helper for subprocess RPC, rather than open-coding JSON writes and reads in every test.
That helper should support:

- start process
- send request
- await response by id
- timeout handling
- graceful shutdown
- forced cleanup on test failure

That helper can itself be reused later by higher-level toolkit integration tests if needed.

## Implementation sequencing for tests

A good test rollout sequence is:

1. protocol codec tests
2. direct worker query tests
3. hub lifecycle helper tests
4. end-to-end open/query/close tests
5. tactic exploration tests
6. file-change and worker-death invalidation tests
7. lower-layer integration hover tests

This mirrors the main implementation phases and reduces the risk of building a large untested process layer all at once.

## Additional implementation findings from the current test harness and existing code

AFTK already has a concrete lightweight test pattern that the server layer should reuse rather than replacing.

- `lakefile.toml` currently sets `testDriver = "aftk_test"`.
- `AFTKTest.Main` aggregates subsystem test lists and exits via `AFTKTest.KnowledgeBase.runTestCases`.
- The shared harness already exists in `AFTKTest.KnowledgeBase.Assert` and provides:
  - `TestCase`
  - `runTestCases`
  - `withTempDir`
  - `assertEq`
  - `assertSome` / `assertNone`
  - `assertContains`
  - `assertJsonParses`
  - `assertThrowsContains`
- `AFTKTest.Informal.Assert` simply re-exports that harness, so the existing project style is to share one small homegrown harness across layers rather than introducing a separate framework.
- Existing CLI tests already use subprocess execution and checked-in fixtures, which means server process tests can follow the same style without adding extra infrastructure first.

Research in the current lower layers also suggests a few testing opportunities that are especially implementation-relevant for the server.

- `AFTK.Informal.Elaborator` already attaches deterministic compact summary text via `renderSummaryText`, so ordinary hover-at-`informal[...]` tests can assert those summary lines directly.
- `AFTK.Informal.Presentation.renderPayloadText` is intentionally deterministic and includes markers such as `[truncated]`, making it a good basis for rich-hover assertions.
- The earlier worker has two quirks worth locking down with explicit regression tests in AFTK:
  - `get_goals` should not allocate hidden fresh nodes
  - and the chosen `load_node` semantics around before-state vs `useAfter` should be asserted directly once AFTK decides them

So the practical testing path is:

- reuse the existing `TestCase` / `runTestCases` harness style
- extend `AFTKTest.Main` rather than creating a second test driver
- add subprocess helpers specialized for newline-delimited JSON-RPC
- and write explicit regression tests for the few known earlier behavioral traps.

## Completion checklist for this plan

This component plan should count as implemented only when all of the following are true in the repository:

- `AFTKTest/Server/*` exists with at least protocol, worker, hub, and process coverage
- `lake test` runs the server-layer suite together with the existing lower-layer suites
- end-to-end process tests cover open/query/close/shutdown and tactic exploration
- file-change invalidation and worker-unavailable cases are covered
- lower-layer integration tests cover hover over `informal[...]` sites backed by real fixtures
- stale-node behavior after restart/reopen is explicitly tested

## Summary

The server/file-worker layer needs both library-level and real subprocess tests.
Its public value lies in operational behavior, so the suite must cover not only successful queries but also the invalidation, restart, and lower-layer-integration cases that higher layers will actually rely on.
