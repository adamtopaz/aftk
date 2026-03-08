# Knowledge Base Serialization Design

## Status

Component plan and implementation-status document for knowledge-base serialization.
This document refines the overall knowledge base plan in `plans/knowledgebase.md` and works together with `plans/knowledgebase/metadata.md`, `plans/knowledgebase/node.md`, `plans/knowledgebase/storage.md`, `plans/knowledgebase/cli.md`, `plans/knowledgebase/validation.md`, and `plans/knowledgebase/search.md`.

## Component implementation status

- Overall status: Implemented for canonical manifest/metadata JSON, Markdown normalization, and CLI JSON output
- Implemented in code: Yes
- Last updated basis: current serialization layer plus CLI JSON envelope rendering

## Purpose

This document defines the serialization rules for the knowledge base layer.
It covers both:

- canonical on-disk serialization for knowledge-base data
- machine-readable JSON output for the CLI

The goal is to make the filesystem representation and automation-facing JSON behavior predictable before implementation begins.

Code has now been added.
This file remains the design reference and status tracker for the implemented serialization rules.

## Design goals

Serialization should:

- preserve the canonical knowledge base in a simple, inspectable form
- round-trip cleanly between Lean values and on-disk representations
- reject malformed canonical JSON rather than silently accepting it
- keep canonical storage deterministic and git-friendly
- provide stable JSON output for higher-layer automation
- clearly separate canonical storage serialization from CLI transport serialization

Lean module and namespace naming for this layer should use `KnowledgeBase` rather than `KB`.
The public CLI should use `lake exe aftk knowledgebase ...`.

## Serialization surfaces

The knowledge base layer has three main serialization surfaces.

### 1. Markdown body files

These store the main prose content of nodes.
They are canonical storage.

### 2. Canonical JSON files

These include:

- `knowledgebase/manifest.json`
- per-node metadata files under `knowledgebase/nodes/**/*.json`

These are canonical storage.

### 3. CLI JSON output

This is not canonical storage.
It is a machine-readable transport format for automation, scripting, and higher layers.

## Core principles

### 1. Canonical storage is strict

Canonical JSON on disk should use a strict schema in v1.
Unknown fields should not be silently ignored.
That helps catch typos and accidental schema drift in manually edited metadata files.

### 2. Canonical storage is deterministic

When the CLI writes canonical JSON, it should do so in a predictable, stable format.
This helps with diffs, testing, and repository review.

### 3. CLI JSON is structured but separate

CLI JSON output should be stable and structured, but it is a different surface from canonical on-disk JSON.
The CLI may include operational context such as command name, root path, warnings, and errors that do not belong in canonical storage.

## Markdown body serialization

Markdown node bodies are stored as plain text in `.md` files.

### Encoding expectations

- files should be read and written as UTF-8 text
- line endings should be normalized by writers to LF (`\n`)
- readers should accept files whether or not they end with a trailing newline
- writers should normally emit a trailing newline for newly written files

### Body-value semantics

The logical body of a node is still just a `String`.
The serialization layer should not interpret Markdown structure semantically in v1.
It only stores and loads the text faithfully.

## Canonical JSON serialization

Canonical JSON applies to at least:

- `StorageManifest`
- `NodeMetadata`
- nested metadata structures such as `Relationship` and `LeanDeclRef`

### Encoding expectations

Canonical JSON files should be:

- UTF-8 encoded
- pretty-printed for human readability
- terminated with a trailing newline when written by the CLI

### Canonical formatting policy

The canonical writer should use a deterministic formatting policy.
For v1, that policy should be:

- 2-space indentation
- stable object key order (and, if the implementation relies directly on `Lean.Json`, that order will naturally be key-sorted)
- no unnecessary whitespace beyond normal pretty-printing
- trailing newline at end of file

## JSON mapping rules for core types

### Wrapper types

The following wrappers should serialize as JSON strings:

- `NodeId`
- `Timestamp`

Examples:

```json
"topology.open_cover"
```

```json
"2026-03-07T21:49:18Z"
```

For v1, `Timestamp` should use a strict UTC whole-second form such as `YYYY-MM-DDTHH:MM:SSZ`.

### Enum-like types

Enum-like Lean types should serialize as predictable JSON strings.
For v1, the strings should use lower camel case matching the current plan examples.

Examples:

- `NodeKind.definition` -> `"definition"`
- `NodeKind.proofSketch` -> `"proofSketch"`
- `NodeStatus.draft` -> `"draft"`
- `RelationshipKind.dependsOn` -> `"dependsOn"`

### Structure types

Structure-like values should serialize as JSON objects.
Their fields should use the field names already used in the design docs unless and until the schema is explicitly revised.

## Canonical metadata JSON contract

### Required fields

For `NodeMetadata`, the initial required fields are:

- `schemaVersion`
- `id`
- `title`

### Optional/defaulted fields

The remaining fields may be omitted when absent or default-valued, subject to the writer policy below.

### Reader policy

The metadata reader should:

- accept omitted optional fields
- accept omitted defaulted collection fields and interpret them as empty
- accept explicitly present default values
- reject unknown fields in v1
- reject malformed field types
- reject unsupported schema versions

In practice, that likely means a manual top-level object reader for canonical metadata rather than relying only on derived `FromJson` instances.

### Writer policy

The metadata writer should produce deterministic JSON.
For v1, it should:

- always emit `schemaVersion`
- always emit `id`
- always emit `title`
- emit other scalar fields when they are present and non-default
- emit array fields when they are nonempty
- omit optional fields whose value is absent
- omit defaulted empty arrays

This keeps metadata readable while preserving stable canonical semantics.

### Operational field management for `NodeMetadata`

The canonical metadata schema is distinct from the operational behavior of CLI mutation commands.
In v1, the intended operational rules are:

- `create` populates both `createdAt` and `updatedAt`
- `body set` refreshes `updatedAt`
- `metadata replace` refreshes `updatedAt`
- `rename` refreshes `updatedAt`
- `metadata replace <id>` must not implicitly change `id`

Those rules should be applied before canonical JSON is written back to disk.

### Field order for `NodeMetadata`

When writing metadata JSON, fields should appear in this order:

1. `schemaVersion`
2. `id`
3. `title`
4. `kind`
5. `status`
6. `summary`
7. `tags`
8. `authors`
9. `createdAt`
10. `updatedAt`
11. `relationships`
12. `leanRefs`

This is a deterministic presentation rule for the canonical writer.
It is not a semantic requirement for readers beyond the normal JSON object model.
If the implementation relies only on `Lean.Json` object emission, preserving this non-lexicographic order will require a tiny custom object writer rather than the default `Json.pretty` path.

## Canonical relationship JSON contract

A `Relationship` should serialize as an object with:

- required: `kind`, `target`
- optional: `label`, `note`

Writer policy:

- always emit `kind`
- always emit `target`
- emit `label` only when present
- emit `note` only when present

Readers should reject unknown fields in v1.

## Canonical Lean reference JSON contract

A `LeanDeclRef` should serialize as an object with:

- required: `declaration`
- optional: `module`, `kind`

Writer policy:

- always emit `declaration`
- emit `module` only when present
- emit `kind` only when present

Readers should reject unknown fields in v1.

## Canonical manifest JSON contract

The root manifest is small and should remain explicit.
Unlike metadata, it is reasonable for the manifest writer to emit all fields even if they currently have default values.

### Reader policy

The manifest reader should:

- require all manifest fields from the v1 schema
- reject unknown fields in v1
- reject unsupported schema versions

As with metadata, a manual top-level object reader is the most direct way to satisfy this strictness policy with Lean's bundled JSON tools.

### Writer policy

The manifest writer should always emit these fields in this order:

1. `schemaVersion`
2. `kind`
3. `nodesDir`
4. `internalDir`

This makes the root self-describing and keeps its structure stable.

## Strictness policy for canonical JSON

In v1, canonical JSON should be intentionally strict.

### Invalid conditions include:

- unknown fields
- missing required fields
- wrong JSON value types
- unsupported schema versions
- invalid enum-string values
- invalid wrapper-field encodings such as non-string `NodeId`

### Duplicate keys

Duplicate object keys should be treated as invalid canonical JSON.
If the underlying JSON parser cannot preserve enough information to detect duplicates directly, the implementation should document that limitation and treat duplicate-key handling as a validator concern.

## CLI JSON output design

CLI JSON output is a separate serialization surface.
It should be stable for automation, but it is not the same thing as canonical storage.

### General envelope

All CLI commands using `--format json` should produce a top-level JSON object.
A reasonable initial common envelope is:

```json
{
  "command": "show",
  "root": "/abs/path/to/knowledgebase",
  "ok": true,
  "result": {},
  "warnings": []
}
```

On failure, the envelope should still be structured:

```json
{
  "command": "show",
  "root": "/abs/path/to/knowledgebase",
  "ok": false,
  "error": {
    "code": "node.notFound",
    "message": "Node not found: topology.open_cover"
  },
  "warnings": []
}
```

### Common CLI JSON fields

The common envelope should use these fields:

- `command : String`
- `root : String`
- `ok : Bool`
- `result? : Json`
- `warnings : Array Json`
- `error? : Json`

The exact command-specific shape of `result` can vary by command, but the outer envelope should stay stable.

### Command-specific payload guidance

#### Node-oriented commands

Commands such as `show`, `create`, and `list` should include node IDs explicitly in their results.
They should not require consumers to parse human text.

#### Validation commands

Validation commands should expose structured issue data, consistent with the validation design.

#### Search commands

Search commands should expose structured hits, consistent with the search design.

## Proposed Lean-level transport types

A conceptual Lean-side transport model could look like this:

```lean
namespace AFTK.KnowledgeBase

structure CliWarning where
  code : String
  message : String

structure CliError where
  code : String
  message : String

structure CliEnvelope (α : Type) where
  command : String
  root : String
  ok : Bool
  result? : Option α := none
  warnings : Array CliWarning := #[]
  error? : Option CliError := none

end AFTK.KnowledgeBase
```

This is only a conceptual model.
The exact implementation can vary, but the stable-envelope idea should remain.

## Interaction with validation

Because canonical JSON is strict in v1, validation and parsing are closely related.
A file may fail at:

- JSON parse level
- schema/field level
- semantic validation level

The implementation should report these clearly rather than collapsing them into opaque generic errors.

## Interaction with mutation commands

Serialization policy should support deterministic writes for commands such as:

- `create`
- `rename`
- `body set`
- `metadata replace`
- future repair/rewrite commands

In particular, commands that rewrite metadata should produce canonical field order and formatting even if the previous file used a different style.

## Recommended first implementation slice

The first serialization implementation should likely prioritize:

1. strict parsing and deterministic writing for `StorageManifest`
2. strict parsing and deterministic writing for `NodeMetadata`
3. UTF-8 Markdown body read/write helpers
4. a stable JSON envelope for CLI output

That is enough to support the first practical command implementations.

## Design decisions for v1

The initial serialization design intentionally does **not** include:

- preservation of comments or non-JSON syntax in metadata files
- tolerant acceptance of unknown canonical JSON fields
- multiple canonical formatting styles
- binary or compressed canonical storage formats
- schema-less CLI JSON output

Those choices may be revisited later, but v1 should prioritize predictability and correctness.

## Lean 4 reuse findings

Lean's bundled JSON support is strong, but it has one important consequence for this design.

- `Lean.Data.Json.parse`, `Json.pretty`, `Json.compress`, `Json.getObjValAs?`, `Json.setObjValAs!`, and `Json.opt` cover most parsing and writing needs.
- `Lean.Elab.Deriving.FromToJson` already registers deriving handlers for `ToJson` and `FromJson`, so leaf enums and simple helper structures can likely use `deriving`.
- `IO.FS.readFile` and `IO.FS.writeFile` already provide UTF-8 text IO for canonical JSON and Markdown files.
- A crucial detail from `Lean.Data.Json.Basic` is that `Json.obj` is backed by `Std.TreeMap.Raw String Json`, and `Json.mkObj` builds objects through that ordered map.
- That means `Json.pretty` naturally gives deterministic key-sorted object output, but it does not preserve an arbitrary custom insertion order.
- Consequently, the implementation has two realistic low-boilerplate choices:
  - align canonical object ordering with the sorted-key behavior of `Lean.Json`, or
  - keep the custom field-order policy from this plan and implement a tiny project-local canonical object writer for those files.
- Likewise, strict unknown-field rejection for canonical files will likely require manual object decoders for top-level manifest and metadata types, since derived `FromJson` for structures does not by itself enforce a no-extra-fields policy.
- `Lake.Util.JsonObject` is a useful bundled helper if we want manual strict decoders without working directly with raw tree maps everywhere.
- `Std.Time.Format` is a good validation and formatting aid for timestamps, but exact canonical `...Z` whole-second output may still want a small wrapper on top of the broader library formats.

## Open questions for later refinement

- Should canonical writers always omit empty arrays, or should some fields be emitted explicitly for readability?
- How aggressively should CLI JSON result schemas be standardized across commands in v1?
- Should future schema evolution include migration tooling or automatic rewriting?
- Should we eventually preserve original formatting for hand-edited files, or always normalize on write?

## Summary

The serialization design separates:

- canonical filesystem serialization for Markdown and JSON storage
- transport-oriented CLI JSON output for automation

Canonical JSON should be strict, deterministic, UTF-8 encoded, and pretty-printed.
Wrapper and enum-like Lean types should have predictable string encodings, and metadata/manifests should follow stable field-order and omission rules.

CLI JSON output should use a stable top-level envelope so that higher layers can consume knowledge-base commands programmatically without scraping human-oriented text.