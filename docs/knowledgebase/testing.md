# Knowledge-base testing

The knowledge-base layer is part of the project-wide Lake test driver.
Run everything with:

```text
lake test
```

Or run only the knowledge-base suite with:

```text
lake exe aftk_knowledgebase_test
```

## Test layout

The knowledge-base tests live under `AFTKTest/KnowledgeBase/`:

```text
AFTKTest/KnowledgeBase/Assert.lean
AFTKTest/KnowledgeBase/Types.lean
AFTKTest/KnowledgeBase/PathLayout.lean
AFTKTest/KnowledgeBase/Serialization.lean
AFTKTest/KnowledgeBase/Storage.lean
AFTKTest/KnowledgeBase/Validation.lean
AFTKTest/KnowledgeBase/Search.lean
AFTKTest/KnowledgeBase/Cli.lean
AFTKTest/KnowledgeBase/Main.lean
```

The aggregate test driver is:

- `AFTKTest/Main.lean`

## Current coverage

The current suite covers:

### Types and low-level validation

- valid `NodeId` cases
- invalid `NodeId` cases
- timestamp validation

### Path layout

- node-id round trips
- canonical path derivation

### Serialization

- manifest golden rendering
- metadata golden rendering
- strict unknown-field rejection for manifest JSON
- strict unknown-field rejection for metadata JSON

### Storage flows

- temporary-directory init/create/load/rename/delete workflows
- paired file creation and reload behavior

### Validation

- broken relationship target detection
- structured validation reporting via library APIs and CLI paths

### Search

- direct-scan text search
- exact tag search

### CLI

- top-level help and subcommand help
- `init` / `create` / `show` happy-path flow
- JSON output smoke coverage

## Fixtures and golden data

Current checked-in test data includes:

```text
tests/knowledgebase/golden/
  manifest.json
  node-metadata.json
```

The suite also uses temporary directories for mutation-heavy tests so repository files are never modified during test execution.

## What the tests intentionally enforce

A few behaviors are treated as important compatibility boundaries:

- `NodeId` acceptance/rejection rules
- deterministic canonical serialization
- strict manifest and metadata parsing
- canonical path mapping
- validation issue detection for broken relationships
- help text availability and CLI entrypoint wiring

## Known testing gaps

The biggest remaining knowledge-base testing gaps are:

- a larger checked-in malformed-root fixture corpus
- broader JSON-contract coverage across every CLI command family
- future repair/indexing coverage once those features exist

## Good rule for extending the suite

When you add or change knowledge-base behavior, prefer this order:

1. update the low-level library test closest to the change
2. add a temporary-directory storage test if filesystem behavior changes
3. add CLI coverage if the public command contract changes
4. add or update goldens only when exact canonical output is part of the contract
