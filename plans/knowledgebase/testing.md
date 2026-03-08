# Knowledge Base Testing Design

## Status

Component plan and implementation-status document for knowledge-base testing.
This document refines the overall knowledge base plan in `plans/knowledgebase.md` and works together with the layout, storage, node, metadata, serialization, CLI, validation, search, repair, and indexing component plans.

## Component implementation status

- Overall status: Implemented for the initial `lake test` driver and core knowledgebase coverage
- Implemented in code: Yes
- Last updated basis: current test driver, harness, golden files, and unit/storage/validation/search/CLI tests

## Purpose

This document defines how the knowledge-base layer should be tested.
It covers unit tests, fixture-backed storage tests, CLI integration tests, regression tests for malformed canonical data, and the role of tests in the implementation sequence.

The goal is to make testing part of the design of the layer rather than something deferred until after most of the implementation is already in place.

Code has now been added.
This file remains the design reference and status tracker for the implemented test strategy.

## Design goals

Testing for the knowledge-base layer should:

- validate the reusable library below the CLI
- validate the CLI as a public interface in its own right
- check canonical filesystem behavior against real temporary directories
- protect deterministic serialization and output contracts from regression
- cover both valid and intentionally invalid storage cases
- remain fast enough for frequent local use
- support future CI automation cleanly
- align with the phased implementation plan in `plans/knowledgebase.md`

Lean module and namespace naming for this layer should use `KnowledgeBase` rather than `KB`.
The public CLI under test should use `lake exe aftk knowledgebase ...`.

## Core testing principles

### 1. Test the library before depending on CLI-only coverage

The knowledge-base layer is primarily a reusable library with a CLI on top.
That means tests should not rely only on end-to-end CLI behavior.

The lower-level modules should be tested directly for things like:

- `NodeId` validation
- path mapping
- metadata parsing and writing
- manifest parsing and writing
- storage operations over temporary directories

CLI tests are still necessary, but they should complement rather than replace library tests.

### 2. Canonical filesystem behavior must be tested against real directories

Path and storage behavior is central to this layer.
Pure tests alone are not enough.

The test suite should create temporary knowledge-base roots and exercise actual filesystem behavior for:

- initialization
- node creation
- load/save cycles
- rename/delete behavior
- validation over malformed roots

### 3. Deterministic canonical output is part of the contract

Canonical JSON formatting, newline normalization, omission/default rules, and stable ordering are not cosmetic details.
They are part of the intended contract.

Tests should therefore assert:

- exact canonical JSON text where appropriate
- expected omission of absent/default fields
- trailing-newline behavior
- deterministic output for repeated writes

### 4. Invalid canonical data needs dedicated regression fixtures

The knowledge base is designed to reject malformed canonical data strictly.
That means the test suite must include intentionally invalid fixture cases such as:

- unknown JSON fields
- invalid enum values
- malformed timestamps
- path/ID mismatch cases
- orphan `.md` or `.json` files
- broken relationship targets
- duplicate node IDs

### 5. JSON output is a stronger compatibility boundary than text output

Human-readable text output matters, but its exact formatting may evolve more than the structured JSON surfaces.
Accordingly:

- CLI JSON output should receive stronger structural assertions
- text output should still be tested, but usually at a lighter level focused on key content and readability

### 6. Tests should land incrementally with implementation phases

The testing plan should not be interpreted as “write tests only after implementation is complete.”
Instead:

- the test harness should be established early
- each implementation phase should add or update tests for the behaviors it introduces
- later regression cases should be added whenever a bug or ambiguity is discovered

## Recommended test layout

A practical initial test layout would be:

```text
AFTKTest/KnowledgeBase/Assert.lean
AFTKTest/KnowledgeBase/Fixtures.lean
AFTKTest/KnowledgeBase/Types.lean
AFTKTest/KnowledgeBase/PathLayout.lean
AFTKTest/KnowledgeBase/Serialization.lean
AFTKTest/KnowledgeBase/Storage.lean
AFTKTest/KnowledgeBase/Cli.lean
AFTKTest/KnowledgeBase/Validation.lean
AFTKTest/KnowledgeBase/Search.lean
AFTKTest/KnowledgeBase/Main.lean
tests/knowledgebase/fixtures/
tests/knowledgebase/golden/
```

This is intentionally simple.
It gives the project:

- Lean test modules close to the implementation domain
- a single place for fixture files that are not Lean source
- room for golden outputs when exact emitted text matters

## Lake target strategy

A good initial test runner strategy is to add a dedicated Lean executable target for the knowledge-base tests, for example:

```toml
[[lean_exe]]
name = "aftk_test"
root = "AFTKTest.KnowledgeBase.Main"
```

The current project uses that pattern through the package test driver, so the main workflow is:

```text
lake test
```

If the test suite later becomes large, it can be split into multiple executables or test groups.
However, one focused knowledge-base test runner is a good first step.

## Test harness design

The first implementation does not need a third-party Lean testing framework.
A small project-local harness under the project-wide `AFTKTest/` tree is sufficient.

### Recommended harness features

The harness should provide utilities such as:

- `assertEq` for comparable values
- `assert` / `assertTrue` for Boolean conditions
- `assertSome` / `assertNone` for options
- `assertErrorContains` for expected failures
- helpers for comparing JSON structurally after parsing
- helpers for exact-text golden comparisons when exact formatting matters
- test grouping and summary reporting

A simple fail-fast harness is acceptable initially, though grouped failure reporting may become more helpful as coverage grows.

## Fixture strategy

The testing plan should use two complementary fixture styles.

### 1. Programmatic fixtures

Small valid objects should often be created directly in Lean code.
Examples:

- a valid `NodeId`
- a `NodeMetadata` value with a few fields
- a small in-memory `Node`

This keeps unit tests explicit and easy to read.

### 2. Filesystem fixtures

Malformed, cross-file, or realism-heavy scenarios should use checked-in fixture directories and files.
Examples:

- a valid minimal root
- a root with orphan files
- a root with path/ID mismatches
- a root with broken relationship targets
- a root with duplicate IDs
- a root with malformed JSON files

These fixtures should live under something like:

```text
tests/knowledgebase/fixtures/
```

and should be copied or materialized into temporary directories before any mutation test runs.

## Recommended fixture cases

The first fixture set should likely include directories like:

```text
tests/knowledgebase/fixtures/
  empty-root/
  minimal-valid-root/
  single-node-valid/
  multi-node-valid/
  orphan-markdown/
  orphan-metadata/
  path-id-mismatch/
  broken-relationships/
  duplicate-ids/
  malformed-manifest/
  malformed-metadata/
```

These names are only illustrative.
The important point is to have small, intention-revealing fixture roots for both valid and invalid scenarios.

## Golden-file strategy

Some behaviors are best tested by exact emitted text.
That is especially true for canonical serialization.

### Good golden-test candidates

- canonical `manifest.json` output
- canonical metadata JSON output
- newline normalization behavior for Markdown writes
- stable CLI JSON envelope examples

### Use golden tests more selectively for text UI

Human text output should still be tested, but it is usually better to avoid overfitting tests to every line of presentation formatting.
For text output, tests should more often assert:

- important headings or labels are present
- node IDs/titles appear as expected
- error messages include key structured facts

instead of pinning every whitespace detail unless the formatting is itself a contract.

## Test categories

### 1. Type and path unit tests

These should test foundational behavior from the node and layout designs.
Examples:

- valid and invalid `NodeId` cases
- dotted-ID to path-stem mapping
- path-stem back to ID reconstruction where supported
- canonical sibling path derivation for `.md` and `.json`
- root path bundle/path helper behavior

These tests should be among the first added because later layers depend on them heavily.

### 2. Serialization tests

These should test canonical serialization rules directly.
Examples:

- `NodeId` and `Timestamp` JSON string mapping
- enum-string mappings
- strict rejection of unknown fields in manifest/metadata readers
- required-field and default-field behavior
- canonical omission of absent/default fields
- deterministic field ordering or deterministic sorted-key output, depending on the final implementation choice
- strict timestamp acceptance/rejection rules
- trailing-newline behavior for emitted JSON and Markdown files

### 3. Storage tests

These should exercise real filesystem operations in temporary directories.
Examples:

- root initialization creates the expected directories and manifest
- create writes both canonical node files
- load returns the expected node value
- body replacement updates Markdown and refreshes `updatedAt`
- metadata replacement preserves identity and refreshes `updatedAt`
- rename updates both file paths and metadata ID together
- delete removes both canonical files
- enumeration finds all canonical nodes and ignores derived state

### 4. CLI integration tests

These should validate the public command surface.
Examples:

- `init`
- `status`
- `list`
- `show`
- `create`
- `body show`
- `body set`
- `metadata show`
- `metadata replace`
- later `validate`, `search`, `relationships`, `reindex`, and `repair`

These tests should check:

- exit codes
- stdout/stderr behavior where relevant
- stable JSON envelope shape under `--format json`
- correct interaction with temporary roots

### 5. Validation tests

These should focus on structured issue reporting.
Examples:

- missing manifest
- unsupported schema version
- orphan canonical files
- path/ID mismatch
- malformed metadata
- invalid timestamps
- broken relationship targets
- duplicate node IDs

The most important assertions here are:

- issue codes
- severities
- scopes
- overall `ok` behavior
- stable JSON serialization of validation reports

### 6. Search tests

These should cover canonical direct-scan semantics before indexing exists.
Examples:

- case-insensitive substring matching in body/title/summary
- exact tag matching
- deterministic node-ID ordering
- result limits
- relationship-oriented discovery commands

### 7. Indexing tests (later)

Once indexing is implemented, tests should check:

- full rebuild behavior
- index-manifest generation
- incoming-relationship index correctness
- equivalence between indexed results and direct-scan results
- safe behavior when indexes are missing, stale, or removed

### 8. Repair tests (later)

Once repair is implemented, tests should check:

- repair-plan construction
- safety classification of proposals
- dry-run versus apply behavior
- quarantine placement for orphan files
- safe normalization of already-parseable manifest/metadata files
- refusal to guess in ambiguous cases such as duplicate IDs or path/ID mismatch without strategy selection

## Temporary-directory policy

Tests that mutate storage should never operate directly on a repository working directory knowledge base.
They should instead:

- create a temporary directory, or
- materialize a checked-in fixture root into a temporary directory,

and then operate only there.

This keeps tests isolated, parallel-friendly, and safe.

## CLI test policy

The CLI is the public interface for this layer, so it needs real command-level tests.
However, CLI tests should be used deliberately.

### Prefer library tests for semantic edge cases

When a failure concerns pure path logic, strict metadata decoding, or validation issue construction, a direct library test is usually more precise and less brittle.

### Prefer CLI tests for public-contract questions

CLI tests are the right place for questions such as:

- which command names/flags exist
- what exit code a failure produces
- what the JSON envelope looks like
- whether text output remains readable and includes key information

## Recommended first implementation slice for testing

The first testing implementation should likely prioritize:

1. a small test executable and assertion harness
2. unit tests for `NodeId` and path/layout helpers
3. serialization tests for manifest and metadata strictness/determinism
4. temporary-directory storage tests for init/create/load/body/metadata flows
5. CLI integration tests for `init`, `create`, `show`, and `status`

After that, the next useful additions are:

- validation regression fixtures
- search tests
- rename/delete tests
- relationship traversal tests

## Interaction with the phased implementation plan

Testing should connect directly to the implementation phases in `plans/knowledgebase.md`.
A sensible mapping is:

- module skeleton phase -> add the test target and harness
- foundational types/path phase -> add unit tests for IDs and path mapping
- serialization/storage phase -> add canonical serialization and temporary-directory storage tests
- CLI MVP phase -> add command-level integration tests
- validation phase -> add invalid-fixture regression tests and issue-code assertions
- search phase -> add direct-scan discovery tests
- indexing phase -> add equivalence tests between direct-scan and indexed behavior
- repair phase -> add dry-run/apply/quarantine tests

That means tests should grow in lockstep with the implementation rather than arriving only at the end.

## Lean 4 reuse findings

Lean's bundled runtime and IO support is already enough for a solid first test harness.

- `IO.FS.createTempDir`, `IO.FS.withTempDir`, `withTempFile`, `readFile`, and `writeFile` cover most temporary-filesystem test needs.
- `System.FilePath` provides the path-computation support needed for fixture and golden-file helpers.
- `Lean.Data.Json.parse` is useful for structural assertions on canonical JSON and CLI JSON output without depending only on exact string comparison.
- `IO.Process.spawn`, `IO.Process.output`, and `IO.Process.run` make it feasible to test the public CLI executable from Lean itself when end-to-end behavior needs coverage.
- No external test framework is strictly required for the first implementation slice; a small project-local assertion harness should be enough.

## Open questions for later refinement

- Should the project keep one knowledge-base test executable, or split library tests and CLI tests into separate targets once coverage grows?
- How much text-output golden testing is worth keeping, given that JSON output is the stronger automation contract?
- Should large malformed-storage fixtures be checked in as directories, or generated programmatically to keep the repository smaller?
- When later layers depend on the knowledge base, should some tests be promoted into broader cross-layer integration suites rather than remaining knowledge-base-local?

## Summary

The knowledge-base layer should have a deliberate testing strategy from the start.
That strategy should combine:

- direct unit tests for core types and path logic
- canonical serialization tests
- temporary-directory storage tests
- CLI integration tests
- regression fixtures for invalid canonical data
- later indexing and repair tests

The first implementation should establish the test harness early and then add coverage phase by phase so that the public knowledge-base library and CLI contracts remain trustworthy as the rewrite grows.