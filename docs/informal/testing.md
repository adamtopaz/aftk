# Informal testing

Run the full project suite with:

```text
lake test
```

Or run only the informal suite with:

```text
lake exe aftk_informal_test
```

## Test layout

The informal tests live under `AFTKTest/Informal/`:

```text
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
```

Supporting Lean fixture modules live under:

```text
AFTKTest/Informal/Fixtures/
```

Filesystem fixtures live under:

```text
tests/informal/knowledgebase-fixtures/
tests/informal/compile-fail/
```

## Current coverage

### Reference handling

- valid node-id parsing
- invalid node-id rejection
- one-segment node ids
- exact resolution against fixture roots
- missing-node behavior
- JSON rendering round trips

### Placeholder primitive

- distinct tags across elaborated definitions
- direct primitive usage at multiple universes
- confirmation that direct primitive use is not tracked automatically

### Tracking

- declaration-centric tracking rows
- reverse reference-centric rows
- imported-state union behavior
- deterministic ordering
- no empty tracked rows

### Dependencies

- declaration dependency projection across imports
- reference dependency projection across imports
- leaf computation
- cycle-safe traversal
- empty-state behavior

### Presentation

- compact summaries include core fields
- preview-mode truncation is deterministic
- full-body mode preserves the whole body
- rich rendering keeps sections sorted and stable

### Elaboration

- successful elaboration in declarations and proofs
- tracked one-segment references
- placeholder construction behavior
- info-tree hover summary smoke test
- compile-fail subprocess tests for:
  - invalid node ids
  - missing nodes
  - malformed node metadata
  - invalid pseudo-context usage

### CLI

- status text output
- declaration and reference queries
- dependency JSON and leaf filtering
- presentation text and JSON paths
- help topics
- failure-path handling

## Fixture roots

### `tests/informal/knowledgebase-fixtures/basic-valid`

Used for most successful resolution, tracking, and CLI tests.
Contains nodes such as:

- `group`
- `group.basic.definition`
- `group.basic.operation_note`
- `algebra.monoid.definition`
- `proof.sketch`

### `tests/informal/knowledgebase-fixtures/long-body`

Used to exercise rich preview truncation and full-body rendering.

### `tests/informal/knowledgebase-fixtures/malformed-node`

Used to confirm that malformed metadata is surfaced as a failure rather than silently ignored.

## Lean fixture modules

Important successful fixture modules include:

- `AFTKTest.Informal.Fixtures.Basic`
- `AFTKTest.Informal.Fixtures.Imports.Base`
- `AFTKTest.Informal.Fixtures.Imports.Mid`
- `AFTKTest.Informal.Fixtures.Imports.Top`
- `AFTKTest.Informal.Fixtures.Deps.Cycle`
- `AFTKTest.Informal.Fixtures.DirectPlaceholder`

These fixtures cover:

- one reference
- repeated identical references
- multiple distinct references
- proof usage
- applied placeholders
- one-segment references
- import-based dependency structure
- cycle handling

## Why the compile-fail tests matter

Negative elaboration cases cannot be tested just by importing a broken module into the main test binary.
Instead the suite compiles dedicated files under `tests/informal/compile-fail/` in subprocesses.

That protects the user-visible behavior of:

- invalid context rejection
- invalid node-id rejection
- missing-node errors
- malformed-node errors

## Helpful extension rule

When changing the informal layer, add tests at the narrowest level that protects the behavior:

1. reference / placeholder / tracking / dependency / presentation unit test
2. successful elaboration fixture test if the change affects real Lean code
3. compile-fail subprocess test if the change affects rejection behavior
4. CLI test if the public command contract changes

## Current blind spots

The current informal suite is already broad, but future work would still benefit from:

- more targeted info-tree rendering checks
- broader JSON contract assertions for every CLI command shape
- additional multi-module dependency fixtures if higher-layer workflow logic grows
