# Knowledge Base Validation Design

## Status

Component plan and implementation-status document for knowledge-base validation.
This document refines the overall knowledge base plan in `plans/knowledgebase.md` and works together with `plans/knowledgebase/storage.md`, `plans/knowledgebase/node.md`, `plans/knowledgebase/metadata.md`, `plans/knowledgebase/cli.md`, and `plans/knowledgebase/repair.md`.

## Component implementation status

- Overall status: Implemented for storage, metadata, node, and whole-root validation
- Implemented in code: Yes
- Last updated basis: current validation issue types, reports, CLI integration, and broken-reference detection

## Purpose

This document defines the validation model for the knowledge base layer.
It describes what should be validated, how validation scopes should be organized, what kinds of issues should be reported, and how validation should connect to the CLI.

Code has now been added.
This file remains the design reference and status tracker for the implemented validation layer.

## Design goals

Validation should:

- detect structural problems in storage, nodes, and metadata
- detect graph-level problems such as broken references between nodes
- produce both human-readable and machine-readable results
- be usable incrementally on a single node or globally on the whole knowledge base
- distinguish errors from warnings cleanly
- remain compatible with file-backed canonical storage
- support later automation and CI-style workflows

Lean module and namespace naming for this layer should use `KnowledgeBase` rather than `KB`.
The public CLI should use `lake exe aftk knowledgebase ...`.

## Validation scope hierarchy

Validation should be organized into layers.
That keeps it modular and lets the CLI expose fast local checks as well as broader integrity checks.

### 1. Storage validation

This validates the knowledge-base root and repository-local storage structure.
Examples:

- root exists
- `manifest.json` exists and parses
- manifest schema version is supported
- `nodes/` exists
- canonical data is not incorrectly stored under `.aftk/`
- manifest-declared paths match the actual layout

This corresponds naturally to:

```text
lake exe aftk knowledgebase validate storage
```

### 2. Node validation

This validates a specific node as a stored object.
Examples:

- Markdown file exists
- JSON metadata file exists
- the two files are correctly paired
- metadata parses successfully
- the node ID is valid syntactically
- path-implied ID matches metadata ID
- no orphaned node half-pair is present

This corresponds naturally to:

```text
lake exe aftk knowledgebase validate node <id>
```

### 3. Metadata validation

This validates the metadata structure independently of broader storage concerns.
Examples:

- required fields exist
- `title` is nonempty
- enum values are recognized
- timestamps use the accepted strict UTC whole-second format
- relationship targets are syntactically valid node IDs
- Lean reference fields are structurally valid

This corresponds naturally to:

```text
lake exe aftk knowledgebase metadata validate <id>
```

### 4. Reference and graph validation

This validates relationships between nodes and other cross-node integrity properties.
Examples:

- relationship targets resolve to existing nodes
- duplicate relationships are detected
- obviously contradictory relationships are flagged
- incoming/outgoing graph views remain coherent with stored metadata

This naturally belongs to broader validation commands such as:

```text
lake exe aftk knowledgebase validate all
```

or later more specialized graph-validation commands if needed.

## Validation levels

The design should distinguish at least two levels of validation effort.

### Local validation

Local validation checks only what can be determined from the targeted object and a small amount of storage context.
It should be fast and suitable for commands that work on a single node.

Examples:

- syntax of node ID
- JSON parseability
- metadata field constraints
- path/ID consistency

### Full validation

Full validation may inspect the entire knowledge base.
It is allowed to be more expensive.

Examples:

- existence of relationship targets
- incoming-edge reconstruction
- duplicate-ID detection across the tree
- full search/index consistency if such checks exist later

## Issue model

Validation results should be structured around explicit issues.
An issue should not just be a raw string.
It should carry enough information for both human display and machine processing.

### Proposed Lean-level types

```lean
namespace AFTK.KnowledgeBase

inductive ValidationSeverity
  | error
  | warning
  | info

inductive ValidationScope
  | storage
  | node (id : NodeId)
  | metadata (id : NodeId)
  | relationships (id : NodeId)
  | wholeKnowledgeBase

structure ValidationIssue where
  code : String
  severity : ValidationSeverity
  scope : ValidationScope
  message : String
  path? : Option System.FilePath := none
  relatedNodeId? : Option NodeId := none

structure ValidationReport where
  ok : Bool
  issues : Array ValidationIssue := #[]

end AFTK.KnowledgeBase
```

This is only a conceptual design.
The exact implementation type can change, but the important idea is that validation emits structured issues rather than only free-form text.

## Recommended validation codes

The implementation should eventually use stable issue codes.
That makes JSON output easier to consume and makes testing more reliable.

Illustrative issue-code families:

### Storage-level codes

- `storage.rootMissing`
- `storage.manifestMissing`
- `storage.manifestParseError`
- `storage.manifestUnknownField`
- `storage.unsupportedSchemaVersion`
- `storage.nodesDirMissing`
- `storage.canonicalDataInInternalDir`

### Node-level codes

- `node.notFound`
- `node.markdownMissing`
- `node.metadataMissing`
- `node.orphanMarkdown`
- `node.orphanMetadata`
- `node.idPathMismatch`
- `node.duplicateId`

### Metadata-level codes

- `metadata.parseError`
- `metadata.missingRequiredField`
- `metadata.emptyTitle`
- `metadata.invalidNodeId`
- `metadata.invalidTimestamp`
- `metadata.invalidEnumValue`
- `metadata.unknownField`

### Relationship-level codes

- `relationships.targetNotFound`
- `relationships.duplicateEdge`
- `relationships.selfEdgeWarning`
- `relationships.contradictoryEdgeWarning`

The exact set can be refined during implementation, but issue codes should be intentional from the start.

## Initial severity policy for v1

The v1 validation policy should classify issues as follows.

### Errors

The following should be treated as errors in v1:

- missing or malformed canonical storage roots and manifests
- unsupported schema versions
- unknown fields in canonical manifest or metadata JSON
- missing canonical Markdown or metadata files
- orphan canonical `.md` or `.json` files
- metadata/path ID mismatches
- duplicate node IDs
- malformed metadata field values, including invalid timestamps
- broken relationship targets during full validation

### Warnings

The following should be warnings in v1:

- exact duplicate relationship edges
- self-relationships
- obviously contradictory relationship combinations when the validator can detect them cheaply

### Informational findings

The following may be informational in v1:

- missing optional internal derived directories such as `.aftk/index/`, `.aftk/cache/`, or `.aftk/tmp/` when they may be created lazily

This policy is intentionally conservative: canonical-storage integrity failures are errors, while graph-shape oddities that may still be semantically intentional remain warnings unless proven otherwise.

## Validation rules by component

### Storage validation rules

Storage validation should check at least:

- whether the configured root exists
- whether the root manifest exists
- whether the manifest parses as JSON
- whether manifest schema version is supported
- whether `nodesDir` exists
- whether canonical node files exist only under the canonical node area
- whether internal/derived directories, if present, are separate from canonical storage

### Node validation rules

Node validation should check at least:

- the node resolves to canonical Markdown and JSON paths
- both files exist
- the metadata parses successfully
- the stored metadata ID is syntactically valid
- the path-derived ID and metadata ID agree
- the Markdown body is loadable as text
- the stored node is not duplicated elsewhere in canonical storage

### Metadata validation rules

Metadata validation should check at least:

- required fields are present
- `schemaVersion` is supported
- `title` is not empty or all-whitespace
- `kind` and `status` are recognized
- tags and authors are well-formed strings
- timestamps follow the accepted strict UTC whole-second format if present, such as `2026-03-07T21:49:18Z`
- relationship records are structurally valid
- Lean references are structurally valid

### Relationship and graph validation rules

Relationship validation should check at least:

- targets are syntactically valid node IDs
- targets exist when running full validation
- exact duplicate edges can be flagged in v1
- suspicious self-references can be warned about
- relationship entries are well-typed and parseable

The first implementation does not need deep semantic graph analysis.
It only needs enough validation to support reliable integrity checking.

## Validation behavior in the CLI

The CLI should expose validation through explicit commands.
The command structure already proposed in `plans/knowledgebase/cli.md` fits this design well.

### `validate storage`

This should run storage-level checks and report root/layout problems.

### `validate node <id>`

This should run a combined per-node validation that includes:

- storage pairing checks
- metadata checks
- local node invariants

### `metadata validate <id>`

This should run metadata-only checks for the node.
It is useful when callers want just schema/field validation without a broader report.

### `validate all`

This should run whole-knowledge-base validation.
It may include:

- storage checks
- per-node checks
- cross-node relationship checks
- duplicate-ID checks
- broken-reference detection

## Output expectations

### Text output

Human-facing validation output should be concise and readable.
A practical style is:

- summary line
- issue count by severity
- issue list grouped by scope or severity

### JSON output

Machine-facing validation output should include at least:

- validation scope
- overall success boolean
- issue list
- per-issue structured fields such as code, severity, message, and optional path/node context

A stable JSON shape is especially important for automation and tests.

## Exit behavior

Validation commands should integrate with the CLI exit-code policy proposed in `plans/knowledgebase/cli.md`.
A natural rule is:

- success with no errors -> exit `0`
- usage problems -> exit `2`
- validation failure with one or more errors -> exit `4`

Warnings alone should not normally force a nonzero exit code.

## Operational strategy

The implementation should prefer validating canonical files directly.
Any derived state or future indexes may help performance, but correctness should not depend on them.

That means:

- storage validation reads the manifest and canonical directories
- node validation reads canonical `.md` and `.json` files
- graph/reference validation may scan canonical node metadata

This keeps validation trustworthy even if caches or indexes are stale.

## Recommended first implementation slice

The first validation implementation should likely prioritize:

1. storage validation
2. metadata validation for a single node
3. node validation for a single node
4. whole-knowledge-base detection of missing relationship targets
5. clear text and JSON reporting

That would give the system useful integrity checks early without requiring an advanced graph-analysis engine.

## Design decisions for v1

The initial validation design intentionally does **not** require:

- sophisticated theorem-level semantic validation
- deep ontology checking of relationship meaning
- validation based on noncanonical caches as the primary source of truth
- automatic repair during ordinary validation commands

Those may come later, but v1 should focus on reliable structural and referential checks.

## Lean 4 reuse findings

The core libraries already cover most of the mechanics needed for structural validation.

- `Std.HashSet.containsThenInsert`, `Std.HashMap.containsThenInsert`, and `getThenInsertIfNew?` are good fits for duplicate-ID and duplicate-edge detection.
- `Std.TreeMap` and `Std.TreeSet` can be used when validation reports need deterministic grouping or sorted output.
- `ValidationSeverity`, `ValidationScope`, `ValidationIssue`, and `ValidationReport` should be able to derive `ToJson` cleanly for CLI output, with custom parsing only where stricter canonical behavior is needed elsewhere.
- `Lean.Data.Json.parse` plus manual object decoding provides enough infrastructure for strict manifest and metadata validation; Lake's manifest code is a good bundled reference for attaching field-specific error context.
- `System.FilePath.metadata`, `symlinkMetadata`, `isDir`, and `pathExists` cover most file-existence and file-kind checks.
- `IO.FS.Metadata` already exposes `type`, `modified`, and `byteSize`, which may be useful for richer diagnostics later.
- `Std.Time.Format` can help validate timestamp strings, but because v1 wants an exact canonical spelling policy, the validator should still enforce the precise accepted form after parsing.
- Domain-specific issue types should remain project-local; the reusable pieces are the parsing, container, and filesystem utilities rather than the issue taxonomy itself.

## Open questions for later refinement

- How much structured repair guidance should validation output include directly, given the separate repair design in `plans/knowledgebase/repair.md`?
- Should validation output include suggestions/fixes in structured form?

## Summary

The knowledge-base validation system should be layered.
It should support storage validation, node validation, metadata validation, and cross-node relationship validation.

Validation results should be emitted as structured issue reports, with both readable text output and stable JSON output.
The CLI should expose this through commands such as:

- `lake exe aftk knowledgebase metadata validate <id>`
- `lake exe aftk knowledgebase validate node <id>`
- `lake exe aftk knowledgebase validate storage`
- `lake exe aftk knowledgebase validate all`

That gives the knowledge base a solid integrity-checking story without requiring a complicated initial implementation.