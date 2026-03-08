# Knowledgebase testing

The project now has a Lake test driver, so the full implemented test suite runs with:

```text
lake test
```

## Lake configuration

The root `lakefile.toml` configures:

- `testDriver = "aftk_test"`
- a dedicated test library root `AFTKTest`
- a dedicated executable target rooted at `AFTKTest.KnowledgeBase.Main`

That means `lake test` builds and runs the knowledgebase test executable automatically.

## Current test coverage

The current suite covers:

- `NodeId` validation
- timestamp validation
- path-layout round trips
- canonical path derivation
- golden manifest rendering
- golden metadata rendering
- strict unknown-field rejection for manifest and metadata JSON
- temporary-directory storage flows for init/create/load/body/rename/delete
- whole-root validation for missing relationship targets
- direct-scan search for text and tags
- CLI smoke coverage for init/create/show with JSON output

The Lean test modules now live under the project-wide `AFTKTest/` tree rather than under the production `AFTK/` library tree.

## Test layout

```text
AFTKTest.lean
AFTKTest/KnowledgeBase.lean
AFTKTest/KnowledgeBase/Assert.lean
AFTKTest/KnowledgeBase/Types.lean
AFTKTest/KnowledgeBase/PathLayout.lean
AFTKTest/KnowledgeBase/Serialization.lean
AFTKTest/KnowledgeBase/Storage.lean
AFTKTest/KnowledgeBase/Validation.lean
AFTKTest/KnowledgeBase/Search.lean
AFTKTest/KnowledgeBase/Cli.lean
AFTKTest/KnowledgeBase/Main.lean
tests/knowledgebase/golden/
```

## Golden files

Current golden files live under:

```text
tests/knowledgebase/golden/
```

They are used for exact canonical serialization checks.

## Extending the suite

When adding behavior, prefer this order:

1. add or update low-level library tests
2. add temporary-directory storage tests if filesystem behavior changes
3. add CLI tests if the public command contract changes
4. add new golden files only when exact emitted text is part of the contract

## Deferred testing work

The main testing items still deferred are:

- a larger checked-in malformed-root fixture suite under `tests/knowledgebase/fixtures/`
- broader CLI JSON coverage across every command family
- repair and indexing tests once those features are implemented
