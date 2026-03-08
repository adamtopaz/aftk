# Informal Testing Design

## Status

Component plan and implementation-status document for informal-layer testing.
This document refines the overall informal-layer plan in `plans/informal.md` and works together with the elaboration, references, placeholder, tracking, dependencies, presentation, CLI, and layout component plans.

## Component implementation status

- Overall status: Not implemented
- Implemented in code: No
- Last updated basis: rewrite worktree currently has no informal-layer test tree; this document is based on the current knowledge-base test structure under `AFTKTest/KnowledgeBase/*`, the informal-layer component plans under `plans/informal/`, and the current main-worktree experience that elaboration- and CLI-heavy behavior needs both imported-module tests and subprocess-style integration tests

## Purpose

This document defines how the informal layer should be tested.
It covers:

- unit tests for reference, placeholder, tracking, dependency, and presentation logic
- elaboration tests for successful `informal[...]` uses in real Lean modules
- compile-fail tests for malformed or unresolved references
- CLI integration tests
- fixture-backed knowledge-base resolution tests
- the role of tests in the implementation sequence

The goal is to make testing part of the design of the informal layer rather than something deferred until after elaboration, tracking, and CLI behavior have already become intertwined.

## Design goals

Testing for the informal layer should:

- validate the reusable library below the CLI
- validate elaboration behavior in real Lean module contexts
- validate declaration-level tracking and dependency derivation over imported modules
- validate knowledge-base-backed resolution and presentation against real fixture roots
- validate the CLI as a public interface in its own right
- cover both successful and intentionally failing elaboration cases
- protect deterministic text/JSON/query behavior from regression
- remain fast enough for frequent local use while still exercising realistic end-to-end paths
- fit cleanly into the project’s `lake test` workflow

Lean module and namespace naming for this layer should use `Informal`, not `Informalize`.
The public CLI under test should use `lake exe aftk informal ...`.

## Core testing principles

### 1. Test the library before depending on CLI-only coverage

The informal layer is primarily a reusable Lean library with a CLI on top.
That means tests should not rely only on end-to-end CLI behavior.

The lower-level modules should be tested directly for things like:

- reference validation and rendering
- exact-match knowledge-base resolution
- placeholder construction assumptions
- tracking aggregation and deduplication
- dependency projection semantics
- presentation summary/payload rendering

CLI tests are still necessary, but they should complement rather than replace library tests.

### 2. Elaboration needs real module tests, not only pure function tests

A large part of the informal layer lives at elaboration time.
So pure runtime tests are not enough.

The test strategy must include real Lean modules that:

- elaborate `informal[...]` successfully,
- populate the persistent environment extension,
- and can then be queried by runtime tests.

This is the only realistic way to validate the integration among:

- syntax,
- reference resolution,
- placeholder construction,
- tracking hooks,
- and hover/info attachment.

### 3. Negative elaboration cases should be subprocess-based

Malformed or unresolved `informal[...]` uses should fail to elaborate.
Those failures cannot be tested only by importing bad modules into the normal test runner, because such modules would break the test build itself.

So compile-fail cases should be tested by spawning Lean/Lake subprocesses against dedicated fixture files and asserting:

- nonzero exit status,
- and key error-message content.

### 4. Knowledge-base-backed behavior must be tested against real fixture roots

Reference resolution and presentation now depend on the knowledge base.
So the test suite must exercise:

- valid fixture roots,
- missing-node cases,
- malformed-node cases,
- and presentation over realistic metadata/body combinations.

Pure in-memory mocks are not enough for these paths.

### 5. Declaration-level tracking is the public contract

The public tracking surface is declaration-level, not per-site.
Tests should therefore assert:

- deduplicated declaration→reference sets,
- reverse reference→declaration views,
- deterministic sorting,
- and absence of empty tracked declarations.

Tests should not accidentally lock the implementation into a per-site public API.

### 6. JSON output is a stronger compatibility boundary than text output

Human-readable text output matters, but the structured JSON outputs are more likely to become automation dependencies.
Accordingly:

- JSON CLI output should receive stronger structural assertions
- text output should still be tested, but usually at a lighter level focused on key content and readability

### 7. Tests should land incrementally with implementation phases

The testing plan should not be interpreted as “write tests only after the informal layer is finished.”
Instead:

- add the test harness early
- add tests alongside each implemented component
- add regression cases whenever a bug or ambiguity is discovered

## Recommended test layout

A practical initial test layout would be:

```text
AFTKTest/Informal.lean
AFTKTest/Informal/Assert.lean
AFTKTest/Informal/Fixtures.lean
AFTKTest/Informal/References.lean
AFTKTest/Informal/Placeholder.lean
AFTKTest/Informal/Tracking.lean
AFTKTest/Informal/Dependencies.lean
AFTKTest/Informal/Presentation.lean
AFTKTest/Informal/Elaboration.lean
AFTKTest/Informal/Cli.lean
AFTKTest/Informal/Main.lean
AFTKTest/Informal/Fixtures/...
tests/informal/knowledgebase-fixtures/...
tests/informal/compile-fail/...
tests/informal/golden/...
```

This extends the layout document’s test tree with two small helper modules:

- `Assert.lean` for a local harness
- `Fixtures.lean` for shared test setup helpers

It also separates:

- Lean fixture modules used for successful elaboration/import,
- filesystem fixture roots for knowledge-base-backed resolution,
- compile-fail source files,
- and optional golden outputs.

## Lake target strategy

The informal-layer tests should fit into the existing package test workflow:

```text
lake test
```

A good initial strategy is:

- add `AFTKTest/Informal/Main.lean` as the informal-suite test runner,
- then make the package-level test driver run both the knowledge-base and informal suites.

Whether that is implemented by:

- a new aggregate `AFTKTest.Main`, or
- an expanded existing test-driver main

is an implementation detail.
The user-facing goal should remain a single `lake test` entrypoint.

## Test harness design

The informal layer does not need a third-party testing framework initially.
A small project-local harness under `AFTKTest/Informal/` is sufficient.

### Recommended harness features

The harness should provide utilities such as:

- `assertEq`
- `assertTrue` / `assertFalse`
- `assertSome` / `assertNone`
- `assertContains` for strings
- `assertErrorContains` for expected failures
- helpers for comparing JSON structurally after parsing
- helpers for running Lean/Lake subprocesses and checking exit codes/output
- helpers for temporary-directory setup and cleanup

If a shared project-wide harness later emerges, the informal suite should use it, but this should not block starting the informal tests.

## Fixture strategy

The informal layer needs several distinct fixture styles.

### 1. Programmatic fixtures

Use ordinary Lean values for small unit-level tests, such as:

- valid and invalid node-id strings for reference validation
- small `InformalReference` values
- small synthetic tracking states
- small presentation summaries/payloads

This keeps low-level tests explicit and easy to read.

### 2. Knowledge-base filesystem fixtures

Use checked-in knowledge-base roots for resolution and presentation tests.
Examples include:

- minimal valid root with one node
- multi-node valid root
- missing target node root
- malformed metadata root
- long-body root for preview/full rendering tests
- relationship-rich root for richer presentation tests

These should live under something like:

```text
tests/informal/knowledgebase-fixtures/
```

and should be copied or materialized into temporary directories before mutation or subprocess tests run.

### 3. Successful elaboration fixture modules

Use small Lean modules that compile successfully and exercise:

- one reference in one declaration
- repeated same reference in one declaration
- multiple references in one declaration
- tracked declarations across imports
- tracked dependency chains with untracked intermediates
- projected reference dependencies

These fixture modules should live under something like:

```text
AFTKTest/Informal/Fixtures/
```

and be imported by the runtime test suite.

### 4. Compile-fail fixture files

Use dedicated Lean source files that are *not* imported by the main test build, but are compiled in subprocesses.
Examples include:

- invalid node-id syntax
- missing knowledge-base node
- malformed knowledge-base node
- `informal[...]` in disallowed command contexts such as `#check`
- possibly bad parser-shape edge cases if the dedicated node-id parser accepts/rejects tricky inputs

These should live under something like:

```text
tests/informal/compile-fail/
```

## Recommended fixture cases

A good first fixture set should include at least the following cases.

### Knowledge-base fixture roots

```text
tests/informal/knowledgebase-fixtures/
  minimal-valid/
  multi-node-valid/
  missing-target/
  malformed-node/
  long-body/
  relationship-rich/
```

### Successful Lean fixture modules

Illustrative groups:

```text
AFTKTest/Informal/Fixtures/
  Basic.lean
  Dedup.lean
  Imports/Base.lean
  Imports/Mid.lean
  Imports/Top.lean
  Deps/Tracked.lean
  Deps/UntrackedHelpers.lean
```

### Compile-fail fixtures

Illustrative groups:

```text
tests/informal/compile-fail/
  invalid-node-id.lean
  missing-node.lean
  malformed-node.lean
  invalid-context-check.lean
```

The exact names are not important.
The important point is to separate success fixtures from failure fixtures cleanly.

## Root-configuration testability requirement

Because `informal[...]` resolution depends on the knowledge-base root, the implementation should remain testable without forcing the suite to mutate the repository’s real top-level `knowledgebase/` directory.

### Recommended testing-friendly design constraint

Reference-resolution and presentation code should support an explicit root/context path in library-level APIs, and CLI tests should use `--root`.

### Why this matters

Without an explicit testable root path, compile-fail and subprocess-based elaboration tests become unnecessarily fragile and may accidentally depend on repository-global state.

This is a testing requirement that should inform implementation choices, even if the exact configuration mechanism is settled elsewhere.

## Golden-file strategy

Some behaviors are best tested by exact emitted text.
For the informal layer, the main golden-test candidates are:

- compact presentation text examples
- rich presentation text examples with body preview/full modes
- selected stable JSON output envelopes for `status`, `deps`, and `present`
- selected compile-fail stderr excerpts where the wording is part of the intended contract

### Use golden tests selectively for human text

As with the knowledge-base layer, ordinary text output should often be tested at the level of key lines or sections rather than every whitespace detail.
Golden tests are most useful where the formatting itself is part of the intended presentation contract.

## Test categories

## 1. Reference unit tests

These should test the reference layer directly.

Examples:

- valid node-id strings become `InformalReference`
- invalid node-id strings are rejected clearly
- one-segment node ids are accepted when valid under the knowledge-base rules
- JSON/string rendering round-trips as expected
- exact-match resolution succeeds for existing nodes and fails for missing nodes

## 2. Placeholder tests

These should test the placeholder mechanism’s basic invariants.

Examples:

- the placeholder primitive is universe polymorphic
- placeholder terms have the expected type shape after elaboration
- distinct source occurrences yield distinct tagged terms
- placeholders do not reduce computationally

Some of these may be tested indirectly through elaboration fixture modules rather than by direct low-level kernel inspection.

## 3. Successful elaboration tests

These should validate that real fixture modules elaborate and produce the intended tracked state.

Examples:

- one declaration referencing one node is tracked
- repeated same reference in one declaration is deduplicated
- multiple different references in one declaration are preserved
- declarations across imports are merged into the extension state correctly
- targeted declaration queries return the expected refs

## 4. Negative elaboration subprocess tests

These should validate deliberate failures.

Examples:

- invalid bracket payload rejects with a validation error
- missing node rejects with a not-found-style error naming the node id
- malformed node rejects with a load/validation-style error naming the node id
- disallowed command-context usage rejects with the intended contextual error

These tests should run Lean/Lake as subprocesses rather than importing the bad files into the normal test build.

## 5. Tracking tests

These should validate the extension and public query surface.

Examples:

- no empty tracked declaration entries are produced
- reverse reference lookup is correct
- imported-state union behaves correctly
- deterministic ordering of declaration and reference rows holds
- direct use of the placeholder primitive alone does not create tracked references unless it flows through `informal[...]`

## 6. Dependency tests

These should validate both declaration and projected reference dependencies.

Examples:

- tracked declaration dependencies traverse through untracked helpers
- self-dependencies are removed
- repeated reachable declarations are deduplicated
- projected reference dependencies union correctly over multiple declarations referencing one node
- dependency leaves match exactly the rows with empty dependency sets
- empty tracking state yields empty dependency results

## 7. Presentation tests

These should validate both compact and richer presentation layers.

Examples:

- compact summaries always include node id and title
- kind/status/summary appear only when appropriate
- rich presentation includes selected optional sections when nonempty
- preview mode truncates deterministically and marks truncation explicitly
- full-body mode returns the whole body when requested
- fallback rendering degrades to at least a minimal summary
- ordering of sections and derived lists is stable

## 8. Hover/info integration smoke tests

If practical in the initial implementation, include smoke tests that validate the elaborator attaches hoverable presentation info at `informal[...]` sites.

These do not need to pin every formatting detail.
They should instead assert things like:

- a hover/info result exists,
- it names the referenced node id,
- and it contains the expected title or summary.

Lean core already provides a practical route for these tests without requiring an external editor session:

- elaborate a file with `IO.processCommands`,
- enable info collection via `commandState.infoState.enabled := true`,
- and inspect the resulting `InfoTree`s.

The current main-worktree file-worker already follows this pattern, so the informal suite should be able to reuse it for positive hover/info smoke coverage.

If full hover/info introspection proves awkward initially, the presentation builders should still be tested directly and the hover integration can begin with lighter smoke coverage.

## 9. CLI integration tests

These should run the actual executable and cover both text and JSON outputs.

Recommended command coverage includes:

- `informal status`
- `informal decls`
- `informal decl <Decl.Name>`
- `informal refs`
- `informal ref <NodeId>`
- `informal deps --by decl`
- `informal deps --by ref`
- `informal deps --only-leaves`
- `informal present --mode compact`
- `informal present --mode rich --body preview`
- `informal present --mode rich --body full`

Recommended failure-path coverage includes:

- missing required `--module`
- invalid `--by`, `--mode`, or `--body` values
- targeted `decl` not tracked
- targeted `ref` not tracked
- invalid node id passed to `ref` or `present`
- missing or malformed knowledge-base node passed to `present`

## JSON contract testing

CLI JSON output should receive stronger structural assertions than text output.
Useful checks include:

- top-level `command` field
- presence of module/target/mode metadata where appropriate
- deterministic row order
- exact field names for declaration/ref/dependency entries
- stable compact/rich presentation payload structure

When feasible, compare parsed JSON structurally rather than by raw string equality.

## Test sequencing recommendation

A sensible implementation/testing order is:

1. reference unit tests and small fixture-root resolution tests
2. placeholder tests
3. successful elaboration fixture modules
4. tracking tests
5. dependency tests
6. presentation tests
7. compile-fail subprocess tests
8. CLI integration tests

This order matches the dependency structure of the layer and keeps failures easier to localize.

## Rejected testing shortcuts

The following shortcuts should be rejected:

### 1. Testing only the CLI

Rejected because the informal layer’s core complexity is in reusable elaboration/tracking/reference logic below the CLI.

### 2. Testing only pure helper functions

Rejected because elaboration-time and environment-extension behavior must be exercised in real Lean modules.

### 3. Using the repository’s real top-level knowledge base as the only test source

Rejected because tests should be isolated and intention-revealing.

### 4. Skipping compile-fail tests because bad modules cannot be imported

Rejected because failure behavior is a major part of the elaboration contract and should be tested through subprocesses.

### 5. Treating dependency leaves as full workflow-frontier tests

Rejected because the informal layer’s leaves are only dependency-derived convenience views, not the full orchestration frontier.

## Lean 4 and current-project reuse findings

The current project already demonstrates several useful testing patterns the informal layer should reuse:

- project-local test runners under `AFTKTest/*`
- a package-level `lake test` entrypoint
- subprocess-based CLI integration testing through `IO.Process`
- deterministic JSON parsing assertions for CLI output
- keeping heavy integration checks in runtime tests rather than relying only on compile-time `run_cmd`

Core Lean also offers two especially relevant hooks for this suite:

- `IO.processCommands` can elaborate files while collecting `InfoTree`s when `infoState.enabled := true`, which is useful for positive hover/info smoke tests
- `Elab.runFrontend` is available when a test wants a fuller frontend-style elaboration path rather than a subprocess

The informal test suite should mirror the successful current-project patterns while adding explicit support for compile-fail elaboration fixtures and knowledge-base-backed presentation/resolution fixtures.

## Open questions for later refinement

- Should the project introduce a shared `AFTKTest.Assert` harness used by both knowledge-base and informal suites, or keep per-suite helpers initially?
- How much direct hover/info-tree introspection should be attempted in v1 tests versus relying on presentation-builder tests plus lighter smoke tests?
- Should compile-fail elaboration fixtures be run through `lake env lean`, a dedicated helper executable, or another small project-local wrapper?

These are testing-framework refinements, not blockers for starting the informal test suite.

## Summary

The informal layer should be tested with a mixed strategy:

- direct library/unit tests,
- successful elaboration fixture modules,
- compile-fail subprocess tests,
- knowledge-base fixture-root tests,
- derived tracking/dependency/presentation tests,
- and end-to-end CLI integration tests.

This strategy matches the actual shape of the informal layer: part reusable library, part elaboration-time integration, part derived graph/query system, and part CLI surface. It also keeps the knowledge-base-backed nature of the rewrite explicit by requiring real fixture roots and by avoiding reliance on the old sidecar-based testing assumptions of the main-worktree `Informalize` design.
