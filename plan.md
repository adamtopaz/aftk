# PRD and Implementation Plan: Informalize Metadata Sidecars and CLI Metadata Management

## Status

Planning only. This document specifies the intended product behavior and implementation plan.
No code changes are made by this document itself.

---

## 1. Overview

We want to extend Informalize so that an `informal[Foo.bar]` node can carry not only markdown notes, but also structured metadata needed for the larger autoformalization workflow.

Today, an Informalize location id resolves only to:

- `informal/Foo/bar.md`

The planned design adds an optional JSON sidecar:

- `informal/Foo/bar.json`

The JSON sidecar stores machine-readable workflow metadata. However, it should **not** be mandatory. If the JSON file does not exist, Informalize should use default metadata.

Agents are expected to manage metadata through the Informalize CLI rather than editing JSON files directly. The CLI should therefore become the supported metadata-management surface. The JSON sidecar is a persistence layer, not the primary user interface.

A second important design point is that dependencies between nodes should **not** be manually stored in the metadata. Instead, they should be computed automatically, similarly to how declaration dependencies are currently computed in the Informalize CLI.

---

## 2. Problem statement

The current Informalize model is useful as a blueprint anchor, but it is missing structured scaffold state needed by the broader workflow in `docs/workflow.md`.

In particular, we need a place to attach information such as:

- node workflow status,
- source references,
- knowledge-base references,
- refinement structure,
- issues/blockers,
- tags or lightweight classification.

At the same time, we do **not** want to:

- force users to author JSON sidecars before they can use `informal[...]`,
- require agents to edit JSON by hand,
- store manually maintained dependency relations that can become stale.

So the system needs:

1. effective default metadata when no JSON sidecar exists,
2. a CLI workflow for reading/updating metadata,
3. automatically derived dependency information.

---

## 3. Goals

### 3.1 Functional goals

1. `informal[Foo.bar]` continues to require `informal/Foo/bar.md`.
2. `informal/Foo/bar.json` becomes optional.
3. If the JSON file is absent, Informalize uses default metadata.
4. If the JSON file is present, it is parsed into a Lean-side metadata type.
5. Metadata is included in hover output for informal nodes.
6. The Informalize CLI can read, initialize, validate, create, and update metadata.
7. Dependency information between informal nodes is computed automatically rather than stored in the JSON.
8. Agents can manage metadata entirely through the CLI.

### 3.2 Workflow goals

1. Preserve the current low-friction workflow where adding `informal[...]` only requires a markdown file.
2. Make metadata adoption incremental: existing informal nodes can acquire metadata over time.
3. Support future workflow orchestration by making key scaffold state machine-readable.
4. Keep source-backed and agent-authored information separable and explicit.

### 3.3 Compatibility goals

1. Existing markdown-backed Informalize projects should continue to elaborate if no `.json` files exist.
2. Existing `deps` declaration output should remain available.
3. The initial implementation should not require AFTK protocol changes.

---

## 4. Non-goals

The first implementation should **not** try to solve all workflow problems at once.

Out of scope for this change:

1. A full knowledge-store implementation.
2. Automatic frontier/readiness orchestration.
3. Persisting derived dependency information into metadata.
4. Making hover dynamically compute and inject dependency summaries.
5. Replacing the current declaration-level extension with a full scaffold graph service.
6. Rich attempt-log persistence.
7. Editing markdown notes through the CLI.

---

## 5. Key product decisions

These decisions are settled for this feature.

### 5.1 Markdown remains required

For `informal[Foo.bar]`, the markdown file remains mandatory:

- required: `informal/Foo/bar.md`

If the markdown file is missing or unreadable, elaboration fails.

### 5.2 JSON metadata is optional

For `informal[Foo.bar]`, the metadata file is optional:

- optional: `informal/Foo/bar.json`

If the JSON file is missing, Informalize uses default metadata.

### 5.3 Invalid JSON is an error

If `informal/Foo/bar.json` exists but is unreadable or invalid, elaboration fails.

Rationale:

- missing metadata is fine,
- malformed metadata should not be silently ignored.

### 5.4 Agents should not edit JSON directly

The supported metadata-management path is the Informalize CLI.

Rationale:

- avoids manual format drift,
- lets us preserve canonical JSON formatting,
- gives agents a stable API,
- allows future validation and migration logic.

### 5.5 Dependencies are derived, not stored

The JSON sidecar should not contain manually authored dependency edges. Dependency information is computed automatically from Lean declaration dependencies plus Informalize location usage.

### 5.6 Refinement structure is authored metadata

Refinement structure should be represented explicitly in metadata, but in a minimal direction.

Planned choice:

- store `parent?` in metadata,
- derive `children` by reverse lookup,
- do not store `children` redundantly.

---

## 6. Conceptual model

The system should distinguish the following concepts.

### 6.1 Persisted metadata

The metadata actually stored on disk in `informal/.../*.json`.

### 6.2 Effective metadata

The metadata the system uses for a location:

- if the `.json` file exists, parse and use it,
- otherwise, use default metadata.

### 6.3 Metadata origin

When reading metadata, it is useful to know whether it came from:

- a file, or
- defaults.

This is relevant for hover, CLI `show`, and validation output.

### 6.4 Scaffold structure

The authored refinement structure of informal nodes.

Planned representation:

- persisted `parent?`,
- derived `children`.

### 6.5 Dependency structure

The automatically computed Lean dependency relation among declarations, projected to informal locations.

This is distinct from scaffold structure.

---

## 7. Proposed metadata model

## 7.1 Design principles

The metadata should be:

- small,
- stable,
- hand-inspectable when needed,
- expressive enough for workflow state,
- not overloaded with data we can derive automatically.

## 7.2 Proposed Lean-side types

The names below are the planned conceptual API. Exact file/module placement can be adjusted during implementation.

### `Informalize.LocationId`

A wrapper around a location id represented canonically as a dotted name string in JSON.

Purpose:

- avoid exposing raw `Lean.Name` JSON internals,
- centralize rendering/parsing,
- share path-resolution logic between elaborator and CLI.

### `Informalize.NodeStatus`

Planned cases:

- `scaffolded`
- `needsSources`
- `needsRefinement`
- `ready`
- `formalizing`
- `formalized`
- `blocked`

Planned JSON encoding:

- `"scaffolded"`
- `"needs_sources"`
- `"needs_refinement"`
- `"ready"`
- `"formalizing"`
- `"formalized"`
- `"blocked"`

### `Informalize.SourceRef`

Planned fields:

- `sourceId : String`
- `anchors : Array String := #[]`
- `locator? : Option String := none`
- `role? : Option String := none`

Purpose:

- link nodes to future source-registry entries,
- preserve basic provenance hooks.

### `Informalize.WorkflowIssue`

Planned fields:

- `id : String`
- `kind : String`
- `refs : Array String := #[]`
- `note : String`

Purpose:

- record blockers/rationale in a structured way,
- support fine-grained CLI add/remove operations.

Typical `kind` values may include:

- `source`
- `dependency`
- `refinement`
- `notation`
- `scope`
- `verification`
- `other`

### `Informalize.Metadata`

Planned fields:

- `schemaVersion : Nat := 1`
- `kind? : Option String := none`
- `status : NodeStatus := .scaffolded`
- `parent? : Option LocationId := none`
- `sources : Array SourceRef := #[]`
- `knowledgeRefs : Array String := #[]`
- `issues : Array WorkflowIssue := #[]`
- `tags : Array String := #[]`

## 7.3 Fields intentionally excluded

The initial metadata should **not** include:

- `dependsOn`
- `children`
- attempt logs
- Lean declaration ownership
- large prose notes

Reason:

- `dependsOn` should be derived automatically,
- `children` should be derived from `parent?`,
- long prose belongs in the markdown file,
- declaration ownership is occurrence-dependent rather than location-intrinsic.

## 7.4 Default metadata

If no JSON file exists, the effective metadata should be the default value:

- `schemaVersion = 1`
- `status = scaffolded`
- everything else empty/none

Conceptually:

```json
{
  "schemaVersion": 1,
  "status": "scaffolded"
}
```

This default need not be materialized on disk unless the CLI is used to initialize or modify metadata.

---

## 8. File/path semantics

For a location id `Foo.bar`:

- markdown path: `informal/Foo/bar.md`
- metadata path: `informal/Foo/bar.json`

For `Foo.bar.baz`:

- markdown path: `informal/Foo/bar/baz.md`
- metadata path: `informal/Foo/bar/baz.json`

The path-mapping rule should be shared between:

- the elaborator,
- metadata loader/saver,
- the CLI.

This likely warrants extracting the current private location-resolution logic into a shared utility module.

---

## 9. Product requirements

## 9.1 Elaborator behavior

### For `informal[Foo.bar]`

The elaborator should:

1. validate the location id syntax,
2. resolve the markdown path,
3. require that the markdown file exists and is readable,
4. resolve the metadata path,
5. if the metadata file exists, parse it,
6. if the metadata file does not exist, use default metadata,
7. attach combined hover text that includes metadata and markdown,
8. continue to register the declaration/location occurrence as today.

### For bare `informal`

Behavior remains unchanged.

No metadata lookup should occur for bare `informal`.

## 9.2 Hover behavior

Hover for an informal location should include:

1. the location id,
2. a metadata-origin indicator (`default` vs `file`),
3. a concise metadata summary,
4. the markdown notes.

The initial hover should include only persisted/effective metadata, not derived dependency summaries.

### Example hover shape

```text
Informalize location: Foo.bar
Metadata source: default

Metadata
--------
status: scaffolded
kind: (none)
parent: (none)
sources: 0
knowledgeRefs: 0
issues: 0
tags: 0

Notes
-----
# Foo.bar
...
```

If file-backed metadata exists, `Metadata source: file` should be shown.

## 9.3 CLI metadata management

The CLI should become the supported interface for reading and mutating metadata.

### Read operations should use effective metadata

If `.json` is absent:

- `meta show` should still succeed,
- `meta validate` should still succeed,
- the result should indicate metadata origin = `default`.

### Write operations should create the JSON file if absent

Mutation commands should:

1. load effective metadata,
2. apply the mutation,
3. write the resulting metadata to `informal/.../*.json`.

This means the first metadata mutation materializes the JSON file.

## 9.4 Dependency computation

Dependency information should be derived automatically.

### Declaration dependencies

Existing declaration dependency computation should be preserved.

### Location dependencies

We should add a location-level projection derived from declaration dependencies.

For a location `L`:

1. find tracked declarations that reference `L`,
2. compute their transitive tracked declaration dependencies using the existing algorithm,
3. collect all informal locations referenced by those dependent declarations,
4. union them,
5. remove `L` itself.

This gives a location dependency relation without storing dependency edges in metadata.

## 9.5 Refinement structure

Metadata should support explicit scaffold refinement structure by storing `parent?`.

Children should be derived by reverse lookup over metadata files/effective metadata.

This does not need to be fully surfaced in the first CLI release, but the data model should support it from the start.

## 9.6 Agent-facing stability requirements

Because agents will use the CLI:

1. command names should be stable,
2. machine-readable output should be available,
3. mutation commands should validate inputs strictly,
4. error messages should be explicit and actionable.

A `--json` output mode should be part of the design from the beginning, even if implemented incrementally.

---

## 10. Proposed CLI surface

## 10.1 Design principles

1. Metadata commands should not require agents to touch JSON directly.
2. Commands that mutate metadata should operate by location id.
3. Commands that compute environment-derived relations should require module imports when necessary.
4. Existing command behavior should remain available where practical.

## 10.2 New metadata namespace

Planned namespace:

- `lake exe informalize meta ...`

This is cleaner than adding many unrelated top-level commands.

## 10.3 Planned metadata commands

### Read/show

- `meta show --location <Location>`
- `meta validate --location <Location>`

### File materialization

- `meta init --location <Location>`

Behavior:

- if no JSON file exists, write the default metadata,
- if JSON exists, leave it unchanged or report success idempotently.

### Scalar-field updates

- `meta set-status --location <Location> --status <Status>`
- `meta set-parent --location <Location> --parent <Location>`
- `meta clear-parent --location <Location>`
- `meta set-kind --location <Location> --kind <Kind>`
- `meta clear-kind --location <Location>`

### Collection updates

- `meta add-tag --location <Location> --tag <Tag>`
- `meta remove-tag --location <Location> --tag <Tag>`
- `meta add-knowledge-ref --location <Location> --ref <Ref>`
- `meta remove-knowledge-ref --location <Location> --ref <Ref>`

### Source management

- `meta add-source --location <Location> --source-id <Id> [--anchor <Anchor>]... [--locator <Locator>] [--role <Role>]`
- `meta remove-source --location <Location> --source-id <Id> [--locator <Locator>]`

Exact removal-key semantics can be finalized during implementation, but removals should be deterministic.

### Issue management

- `meta add-issue --location <Location> --id <IssueId> --kind <Kind> --note <Note> [--ref <Ref>]...`
- `meta remove-issue --location <Location> --id <IssueId>`

Issue ids are important so agents can manage individual issues reliably.

## 10.4 Dependency commands

### Existing behavior

Keep the current declaration-oriented dependency behavior available.

### Planned extension

Extend `deps` to support modes such as:

- `deps --by decl`
- `deps --by location`

Backward-compatibility plan:

- default `deps` behavior remains declaration-oriented unless deliberately changed later.

Location-mode output should present derived location dependencies rather than stored metadata edges.

## 10.5 Future scaffold-structure queries

Not required in the first code change, but planned as natural follow-ons:

- `children --location <Location>`
- `frontier --module <Module>`

These should be built from authored `parent?` metadata plus derived status filters, not from stored dependency lists.

## 10.6 Output modes

Planned output modes:

- default plain-text output for humans,
- `--json` output for agents.

This is especially important for:

- `meta show`
- `meta validate`
- `deps --by location`
- future `children` / `frontier`

---

## 11. Error model

## 11.1 Elaborator errors

### Missing markdown file

Still an error:

- `informal id 'Foo.bar' points to missing file 'informal/Foo/bar.md'`

### Missing metadata file

Not an error.

Use default metadata.

### Unreadable metadata file

Error.

### Invalid metadata JSON

Error.

Suggested style:

- `invalid metadata in 'informal/Foo/bar.json' for informal id 'Foo.bar': ...`

## 11.2 CLI errors

### Metadata read commands

- missing markdown file: error
- missing JSON file: not an error
- invalid JSON file: error

### Metadata mutation commands

- missing markdown file: error
- missing JSON file: not an error; create it
- invalid JSON file: error

### Dependency commands

Errors should remain explicit when required module imports are missing or malformed.

---

## 12. Architecture and module plan

## 12.1 New/shared functionality likely needed

### Shared location/path utilities

Current location-id parsing/path construction logic is private to `Informalize/Elaborator.lean`.

Because the CLI also needs:

- location parsing,
- dotted-name rendering,
- `.md` path derivation,
- `.json` path derivation,

we should extract this into a shared utility module.

Possible module names:

- `Informalize/Location.lean`
- `Informalize/Path.lean`

This module should centralize:

- dotted location parsing/rendering,
- path mapping rules,
- validation constraints.

### Metadata module

Add a new module:

- `Informalize/Metadata.lean`

Responsibilities:

- metadata types,
- JSON encoding/decoding,
- effective-metadata loading,
- metadata origin tracking,
- canonical save/write helpers,
- hover-summary rendering.

## 12.2 Existing files likely to change

### `Informalize.lean`

Export the new metadata module and any shared location utilities.

### `Informalize/Elaborator.lean`

Refactor location resolution so that:

- markdown remains required,
- metadata is optional with default fallback,
- hover includes metadata summary + markdown.

### `Informalize/Cli.lean`

Extend the parser, config, and command execution layer to support:

- metadata commands,
- metadata loading/writing,
- location-level dependency queries,
- optional JSON output.

### Potentially `Informalize/Extension.lean`

Likely no fundamental schema change is required for v1, since the extension can continue tracking declaration -> locations. But helper queries may be added to support location projection cleanly.

### AFTK / TypeScript layers

Probably no changes are required initially, because AFTK hover already relays Lean hover text. If Informalize hover text changes, the existing AFTK stack should surface it automatically.

---

## 13. Detailed implementation plan

## Phase 0: finalize data model and CLI contract

Deliverables:

- settled metadata schema,
- settled CLI surface,
- settled dependency-derivation rules,
- settled hover summary shape.

This document is Phase 0.

## Phase 1: shared location/path utilities

Tasks:

1. Extract location parsing/rendering logic out of `Informalize/Elaborator.lean`.
2. Provide shared helpers for:
   - dotted id parsing,
   - `LocationId` conversion,
   - markdown path derivation,
   - metadata path derivation.
3. Preserve existing validation behavior:
   - at least two components,
   - no numeric components.

Acceptance:

- elaborator and CLI can both use the same path/validation logic.

## Phase 2: metadata types and effective-metadata loading

Tasks:

1. Add `Informalize/Metadata.lean`.
2. Define:
   - `LocationId`
   - `NodeStatus`
   - `SourceRef`
   - `WorkflowIssue`
   - `Metadata`
   - `MetadataOrigin`
   - optionally `LoadedMetadata`
3. Implement `ToJson` / `FromJson`.
4. Prefer explicit/manual JSON handling where it improves stability, especially for:
   - status string encoding,
   - defaults,
   - location-id encoding.
5. Implement helpers for:
   - default metadata,
   - loading effective metadata,
   - loading persisted metadata optionally,
   - writing canonical metadata JSON.

Acceptance:

- metadata can be loaded from disk or synthesized from defaults,
- a caller can tell whether metadata origin is `default` or `file`.

## Phase 3: elaborator integration and hover rendering

Tasks:

1. Extend the resolved-informal-id path to load effective metadata.
2. Keep markdown required.
3. If metadata file is missing, use defaults.
4. If metadata file is malformed, fail elaboration.
5. Replace raw markdown-only hover text with combined hover text:
   - location id,
   - metadata origin,
   - metadata summary,
   - markdown notes.
6. Preserve current occurrence tracking behavior.

Acceptance:

- existing markdown-only informal nodes still elaborate,
- hover includes effective metadata even when `.json` is absent.

## Phase 4: CLI metadata commands

Tasks:

1. Extend CLI command model to add `meta` namespace.
2. Add read commands:
   - `meta show`
   - `meta validate`
   - `meta init`
3. Add mutation commands for:
   - status,
   - parent,
   - kind,
   - tags,
   - knowledge refs,
   - sources,
   - issues.
4. Mutation commands should:
   - load effective metadata,
   - apply update,
   - write canonical JSON.
5. Decide and implement atomic write strategy.
6. Add optional `--json` output mode, at least for metadata commands.

Acceptance:

- agents can create and manage metadata through CLI without editing files manually,
- first metadata mutation creates the JSON sidecar if absent.

## Phase 5: location-level dependency queries

Tasks:

1. Preserve current declaration dependency output.
2. Add location-level dependency projection.
3. Extend `deps` or add a related query mode to expose derived location dependencies.
4. Keep output available in both plain text and structured JSON.

Acceptance:

- dependency edges between informal nodes are available without being stored in metadata.

## Phase 6: documentation and examples

Tasks:

Update at least:

- `README.md`
- `docs/informalize/README.md`
- `docs/informalize/IdReference.md`
- `docs/agent-playbook.md`
- `docs/workflow.md` if terminology/examples need adjustment
- `docs/future/autoformalization-tools.md` if roadmap positioning changes

Docs should explain:

- `.md` required / `.json` optional semantics,
- default metadata behavior,
- CLI-based metadata management,
- dependency derivation,
- hover behavior.

Acceptance:

- docs describe the implemented behavior accurately and give agent-usable examples.

---

## 14. Test plan

## 14.1 Unit tests for metadata model

Add tests for:

- `NodeStatus` JSON encoding/decoding,
- `LocationId` dotted-string JSON encoding/decoding,
- metadata defaulting behavior,
- malformed metadata rejection,
- metadata roundtrips where appropriate.

## 14.2 Elaborator tests

Add/adjust tests for:

- `informal[...]` with markdown present and JSON absent,
- `informal[...]` with valid JSON present,
- `informal[...]` with malformed JSON,
- `informal[...]` with unreadable/missing markdown,
- unchanged behavior for bare `informal`.

## 14.3 Hover-format tests

There are currently no AFTK hover integration tests in the Lean test suite.

Initial recommendation:

- factor metadata hover rendering into a pure function and test that function directly.

This gives strong coverage without immediately expanding AFTK integration testing.

## 14.4 CLI tests

Add integration/runtime tests for:

- `meta show` on a location with no JSON file,
- `meta init` materializing default JSON,
- `meta set-status` creating JSON when absent,
- tag/source/issue add/remove commands,
- validation errors for malformed metadata,
- `deps --by location` or equivalent location-level dependency mode.

## 14.5 Fixture updates

Existing fixtures can remain markdown-only in many cases, since JSON is optional.

Add a small number of explicit `.json` fixtures for:

- valid file-backed metadata,
- malformed JSON,
- representative status/source/issue data.

---

## 15. Acceptance criteria

The feature is complete when all of the following hold.

### Core behavior

1. Existing markdown-backed `informal[...]` terms elaborate without requiring `.json` files.
2. If a JSON sidecar exists and is valid, it is parsed and used.
3. If a JSON sidecar exists and is invalid, elaboration fails clearly.
4. Hover includes metadata information plus markdown notes.

### CLI behavior

5. `meta show` works whether or not the JSON file exists.
6. Metadata mutation commands create the JSON file on demand.
7. Agents can update metadata without editing JSON directly.

### Dependency behavior

8. Declaration dependency queries still work.
9. Location/node dependency queries are available and derived automatically.
10. No manually authored dependency edges are stored in metadata.

### Documentation/testing

11. Relevant docs are updated.
12. Tests cover default metadata, file-backed metadata, CLI mutation, and derived dependencies.

---

## 16. Risks and mitigation

## 16.1 Risk: conflating scaffold structure and dependency structure

Mitigation:

- explicitly keep `parent?`-based scaffold structure separate from automatically derived dependencies.

## 16.2 Risk: unstable agent interaction if CLI output is only text

Mitigation:

- plan `--json` output early,
- use stable field names and machine-readable errors.

## 16.3 Risk: duplicated path-resolution logic between elaborator and CLI

Mitigation:

- extract shared location/path helpers before adding CLI metadata management.

## 16.4 Risk: malformed metadata silently breaking user expectations

Mitigation:

- treat present-but-invalid JSON as an elaboration/CLI error,
- provide explicit validation command.

## 16.5 Risk: hover becomes noisy

Mitigation:

- render a concise metadata summary rather than dumping raw JSON by default.

---

## 17. Migration and compatibility

This change should be backward-compatible for existing markdown-only projects.

Migration story:

1. existing nodes keep working with `.md` only,
2. metadata is introduced incrementally,
3. the CLI can materialize sidecars on demand,
4. dependency information is added without requiring metadata edits.

No bulk migration should be required.

---

## 18. Recommended implementation order

Recommended order of work:

1. shared location/path utilities,
2. metadata types + effective-metadata loader/writer,
3. elaborator hover integration,
4. CLI metadata commands,
5. location dependency queries,
6. docs/tests cleanup.

This order preserves backward compatibility early while unlocking agent-facing metadata management quickly.

---

## 19. Summary of the intended user experience

### Authoring a new informal node

1. create `informal/Foo/bar.md`
2. write `informal[Foo.bar]` in Lean
3. elaboration succeeds even if `informal/Foo/bar.json` does not exist
4. hover shows default metadata + notes

### Adding metadata later

1. run `lake exe informalize meta init --location Foo.bar`
2. or directly run `lake exe informalize meta set-status --location Foo.bar --status ready`
3. the CLI creates/updates `informal/Foo/bar.json`
4. hover now reflects file-backed metadata

### Querying dependencies

1. run `lake exe informalize deps --module My.Module`
2. optionally request location/node mode
3. use the derived dependency information without manually maintaining dependency fields in metadata

This is the intended product direction for the first metadata-enabled Informalize release.
